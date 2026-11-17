package core

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/metacubex/http"
	"github.com/metacubex/mihomo/constant"
)

// Kept apart from the host's own record: the guard decides on these verdicts
// alone, and a restart must not hold traffic back while every node is checked.
const purityFile = "sloth-purity.json"

type purityLevel uint8

const (
	purityUnknown purityLevel = iota
	purityGood
	purityNormal
	purityRisky
)

var (
	// A node's address is confirmed again once purityFresh has passed, and a
	// clean verdict keeps its traffic flowing meanwhile until purityTrusted.
	purityFresh   = 30 * time.Minute
	purityTrusted = 6 * time.Hour
	purityRetry   = 15 * time.Second
	// Kept in step with ipQualityMaxAge in lib/providers/ip_quality.dart.
	ipVerdictKeep = 3 * 24 * time.Hour
	puritySave    = 10 * time.Second

	lookupNodeExit  = lookupExitOf
	lookupIpVerdict = queryIpVerdict
	// Set by the guard, which acts on a node that turned unclean.
	purityChanged func(node string, level purityLevel)
)

type ipVerdict struct {
	Type   string `json:"type"`
	Source string `json:"source"`
	Tor    bool   `json:"tor,omitempty"`
	Abuser bool   `json:"abuser,omitempty"`
	At     int64  `json:"at"`
}

// Mirrors IpQualityExt.level in lib/models/ip_quality.dart.
func (v ipVerdict) level() purityLevel {
	if v.Tor || v.Abuser {
		return purityRisky
	}
	switch v.Type {
	case "residential", "mobile", "business":
		return purityGood
	case "hosting":
		return purityNormal
	}
	return purityUnknown
}

type nodeAddress struct {
	Ip string `json:"ip"`
	At int64  `json:"at"`
}

type purityRecord struct {
	Nodes map[string]nodeAddress `json:"nodes"`
	Ips   map[string]ipVerdict   `json:"ips"`
}

type purityBook struct {
	mu       sync.Mutex
	writing  sync.Mutex
	loaded   bool
	record   purityRecord
	checking map[string]bool
	failed   map[string]time.Time
	saving   bool
}

var purity = &purityBook{}

// levelLocked answers from what is known; due is set once the node should be
// checked again.
func (b *purityBook) levelLocked(node string, now time.Time) (level purityLevel, due bool) {
	b.load()
	address, ok := b.record.Nodes[node]
	if !ok {
		return purityUnknown, true
	}
	verdict, ok := b.record.Ips[address.Ip]
	if !ok {
		return purityUnknown, true
	}
	age := now.Sub(time.UnixMilli(address.At))
	if age >= purityTrusted {
		return purityUnknown, true
	}
	due = age >= purityFresh || now.Sub(time.UnixMilli(verdict.At)) >= ipVerdictKeep
	return verdict.level(), due
}

// cleared is the guard's fast path: clean and checked lately, so nothing
// needs asking.
func (b *purityBook) cleared(node string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	level, due := b.levelLocked(node, time.Now())
	return level == purityGood && !due
}

// levelOf starts a check when the verdict is missing or due.
func (b *purityBook) exitOf(node string) string {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.load()
	return b.record.Nodes[node].Ip
}

func (b *purityBook) levelOf(node string) purityLevel {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := time.Now()
	level, due := b.levelLocked(node, now)
	if due {
		b.ensureLocked(node, now)
	}
	return level
}

func (b *purityBook) allows(node string) bool {
	return b.levelOf(node) == purityGood
}

func (b *purityBook) ensureLocked(node string, now time.Time) {
	if b.checking[node] {
		return
	}
	if failed, ok := b.failed[node]; ok && now.Sub(failed) < purityRetry {
		return
	}
	b.checking[node] = true
	go b.check(node)
}

func (b *purityBook) check(node string) {
	exit := lookupNodeExit(node)
	if exit.ip == "" {
		b.fail(node)
		return
	}
	b.checkAddress(node, exit.ip)
}

func (b *purityBook) checkAddress(node, ip string) {
	b.mu.Lock()
	verdict, known := b.record.Ips[ip]
	b.mu.Unlock()
	if !known || time.Since(time.UnixMilli(verdict.At)) >= ipVerdictKeep {
		var err error
		if verdict, err = lookupIpVerdict(node, ip); err != nil {
			b.fail(node)
			return
		}
		verdict.At = time.Now().UnixMilli()
	}
	b.settle(node, ip, verdict)
}

func (b *purityBook) settle(node, ip string, verdict ipVerdict) {
	b.mu.Lock()
	now := time.Now()
	before, _ := b.levelLocked(node, now)
	b.record.Nodes[node] = nodeAddress{Ip: ip, At: now.UnixMilli()}
	b.record.Ips[ip] = verdict
	delete(b.failed, node)
	b.scheduleSaveLocked()
	b.mu.Unlock()
	if after := verdict.level(); after != before {
		purityChanged(node, after)
	}
	b.mu.Lock()
	delete(b.checking, node)
	b.mu.Unlock()
}

func (b *purityBook) fail(node string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	delete(b.checking, node)
	b.failed[node] = time.Now()
}

// observe takes an address the exit record found for a node it knows: the
// same one confirms the node, a new one leaves it unknown until checked.
func (b *purityBook) observe(node, ip string) {
	if ip == "" {
		return
	}
	b.mu.Lock()
	address, known := b.record.Nodes[node]
	if !b.loaded || !known {
		b.mu.Unlock()
		return
	}
	now := time.Now()
	if address.Ip == ip {
		b.record.Nodes[node] = nodeAddress{Ip: ip, At: now.UnixMilli()}
		b.scheduleSaveLocked()
		b.mu.Unlock()
		return
	}
	before, _ := b.levelLocked(node, now)
	delete(b.record.Nodes, node)
	start := !b.checking[node]
	b.checking[node] = true
	b.mu.Unlock()
	if before != purityUnknown {
		purityChanged(node, purityUnknown)
	}
	if start {
		go b.checkAddress(node, ip)
	}
}

func (b *purityBook) load() {
	if b.loaded {
		return
	}
	b.loaded = true
	b.checking = map[string]bool{}
	b.failed = map[string]time.Time{}
	b.record = purityRecord{Nodes: map[string]nodeAddress{}, Ips: map[string]ipVerdict{}}
	var stored purityRecord
	if buf, err := os.ReadFile(purityPath()); err == nil && json.Unmarshal(buf, &stored) == nil {
		for node, address := range stored.Nodes {
			b.record.Nodes[node] = address
		}
		for ip, verdict := range stored.Ips {
			b.record.Ips[ip] = verdict
		}
	}
	b.pruneLocked(time.Now())
}

func (b *purityBook) pruneLocked(now time.Time) {
	used := map[string]bool{}
	for node, address := range b.record.Nodes {
		if now.Sub(time.UnixMilli(address.At)) >= purityTrusted {
			delete(b.record.Nodes, node)
			continue
		}
		used[address.Ip] = true
	}
	for ip, verdict := range b.record.Ips {
		if !used[ip] && now.Sub(time.UnixMilli(verdict.At)) >= ipVerdictKeep {
			delete(b.record.Ips, ip)
		}
	}
}

func (b *purityBook) scheduleSaveLocked() {
	if b.saving {
		return
	}
	b.saving = true
	time.AfterFunc(puritySave, b.save)
}

func (b *purityBook) save() {
	b.writing.Lock()
	defer b.writing.Unlock()
	b.mu.Lock()
	b.saving = false
	b.pruneLocked(time.Now())
	buf, err := json.Marshal(b.record)
	b.mu.Unlock()
	if err != nil {
		return
	}
	path := purityPath()
	temporary := path + ".tmp"
	if os.WriteFile(temporary, buf, 0o600) == nil {
		_ = os.Rename(temporary, path)
	}
}

func purityPath() string {
	return filepath.Join(constant.Path.HomeDir(), purityFile)
}

// The sources and waves follow lib/common/ip_quality.dart, less ident.me: it
// reports whoever asks, and the host never asks through the node, so the two
// would take different first answers.
var (
	qualityHedge   = time.Second
	qualityTimeout = 8 * time.Second
	qualityMaxBody = int64(64 << 10)
	askQuality     = askQualitySource
	qualityWaves   = [][]qualitySource{
		{ipApiComSource, ipQuerySource},
		{ipLocateSource},
		{ipApiIsSource},
		{proxyCheckSource},
	}
)

var (
	errQualityFailed      = errors.New("quality source failed")
	errQualityRateLimited = errors.New("quality source rate limited")
	errQualityNoType      = errors.New("quality source names no type")
)

type qualitySource struct {
	name  string
	url   func(ip string) string
	parse func(ip string, body map[string]any) (verdict ipVerdict, inferred bool, err error)
}

type qualityAnswer struct {
	verdict  ipVerdict
	inferred bool
	err      error
}

// queryIpVerdict asks through the node itself, as the guard may block every
// other way out. A source that only stays silent about hosting answers
// residential, which stands only if no source names a type.
func queryIpVerdict(node, ip string) (ipVerdict, error) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	answers := make(chan qualityAnswer, 8)
	ask, wave, inFlight := askQuality, 0, 0
	launch := func() {
		for _, source := range qualityWaves[wave] {
			inFlight++
			go func(source qualitySource) {
				answer := ask(ctx, source, node, ip)
				answer.verdict.Source = source.name
				answers <- answer
			}(source)
		}
		wave++
	}
	launch()
	hedge := time.NewTimer(qualityHedge)
	defer hedge.Stop()
	var fallback *ipVerdict
	for {
		select {
		case answer := <-answers:
			inFlight--
			if answer.err == nil && !answer.inferred {
				return answer.verdict, nil
			}
			if answer.err == nil && fallback == nil {
				fallback = &answer.verdict
			}
			if inFlight > 0 {
				continue
			}
			if wave < len(qualityWaves) {
				launch()
				hedge.Reset(qualityHedge)
				continue
			}
			if fallback != nil {
				return *fallback, nil
			}
			return ipVerdict{}, errQualityFailed
		case <-hedge.C:
			if wave < len(qualityWaves) {
				launch()
				hedge.Reset(qualityHedge)
			}
		}
	}
}

func askQualitySource(ctx context.Context, source qualitySource, node, ip string) qualityAnswer {
	result := runProbe(ctx, probeRequest{
		method:    http.MethodGet,
		url:       source.url(ip),
		proxyName: node,
		headers:   map[string]string{"User-Agent": browserUserAgent},
		timeout:   qualityTimeout,
		maxBody:   qualityMaxBody,
	})
	switch {
	case result == nil || result.Error != "":
		return qualityAnswer{err: errQualityFailed}
	case result.StatusCode == http.StatusTooManyRequests:
		return qualityAnswer{err: errQualityRateLimited}
	case result.StatusCode != http.StatusOK:
		return qualityAnswer{err: errQualityFailed}
	}
	var body map[string]any
	if err := json.Unmarshal([]byte(result.Body), &body); err != nil {
		return qualityAnswer{err: errQualityFailed}
	}
	verdict, inferred, err := source.parse(ip, body)
	return qualityAnswer{verdict: verdict, inferred: inferred, err: err}
}

var ipApiComSource = qualitySource{
	name: "ipApiCom",
	// ip-api.com serves HTTPS only on its paid plan.
	url: func(ip string) string {
		return "http://ip-api.com/json/" + ip + "?fields=status,isp,org,as,mobile,proxy,hosting"
	},
	parse: func(_ string, body map[string]any) (ipVerdict, bool, error) {
		if body["status"] != "success" {
			return ipVerdict{}, false, errQualityFailed
		}
		return inferredVerdict(ipVerdict{Type: pickKind(flag(body["hosting"]), flag(body["mobile"]), "")})
	},
}

var ipQuerySource = qualitySource{
	name: "ipQuery",
	url:  func(ip string) string { return "https://api.ipquery.io/" + ip + "?format=json" },
	parse: func(_ string, body map[string]any) (ipVerdict, bool, error) {
		risk := object(body["risk"])
		return inferredVerdict(ipVerdict{
			Type: pickKind(flag(risk["is_datacenter"]), flag(risk["is_mobile"]), ""),
			Tor:  flag(risk["is_tor"]),
		})
	},
}

var ipLocateSource = qualitySource{
	name: "ipLocate",
	url:  func(ip string) string { return "https://iplocate.io/api/lookup/" + ip },
	parse: func(_ string, body map[string]any) (ipVerdict, bool, error) {
		privacy := object(body["privacy"])
		return statedVerdict(ipVerdict{
			Type:   pickKind(flag(privacy["is_hosting"]), false, companyKind(body)),
			Tor:    flag(privacy["is_tor"]),
			Abuser: flag(privacy["is_abuser"]),
		})
	},
}

var ipApiIsSource = qualitySource{
	name: "ipApiIs",
	url:  func(ip string) string { return "https://api.ipapi.is/?q=" + ip },
	parse: func(_ string, body map[string]any) (ipVerdict, bool, error) {
		return statedVerdict(ipVerdict{
			Type:   pickKind(flag(body["is_datacenter"]), flag(body["is_mobile"]), companyKind(body)),
			Tor:    flag(body["is_tor"]),
			Abuser: flag(body["is_abuser"]),
		})
	},
}

var proxyCheckSource = qualitySource{
	name: "proxyCheck",
	url:  func(ip string) string { return "https://proxycheck.io/v3/" + ip },
	parse: func(ip string, body map[string]any) (ipVerdict, bool, error) {
		switch body["status"] {
		case "denied":
			return ipVerdict{}, false, errQualityRateLimited
		case "ok", "warning":
		default:
			return ipVerdict{}, false, errQualityFailed
		}
		result := object(body[ip])
		network, detections := object(result["network"]), object(result["detections"])
		networkType, _ := network["type"].(string)
		declared := map[string]string{"Residential": "residential", "Business": "business"}[networkType]
		return statedVerdict(ipVerdict{
			Type: pickKind(flag(detections["hosting"]) || networkType == "Hosting", networkType == "Wireless", declared),
			Tor:  flag(detections["tor"]),
		})
	},
}

func inferredVerdict(verdict ipVerdict) (ipVerdict, bool, error) {
	if verdict.Type == "" {
		verdict.Type = "residential"
		return verdict, true, nil
	}
	return verdict, false, nil
}

func statedVerdict(verdict ipVerdict) (ipVerdict, bool, error) {
	if verdict.Type == "" {
		return verdict, false, errQualityNoType
	}
	return verdict, false, nil
}

func pickKind(hosting, mobile bool, declared string) string {
	switch {
	case hosting || declared == "hosting":
		return "hosting"
	case mobile:
		return "mobile"
	}
	return declared
}

func companyKind(body map[string]any) string {
	if kind := declaredKind(object(body["company"])["type"]); kind != "" {
		return kind
	}
	return declaredKind(object(body["asn"])["type"])
}

func declaredKind(value any) string {
	switch value {
	case "isp":
		return "residential"
	case "business", "education", "government", "banking":
		return "business"
	case "hosting":
		return "hosting"
	}
	return ""
}

func object(value any) map[string]any {
	if fields, ok := value.(map[string]any); ok {
		return fields
	}
	return map[string]any{}
}

func flag(value any) bool {
	return value == true
}
