package core

import (
	"encoding/json"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

// The host reads this file itself, so the record outlives the Core.
const appExitsFile = "sloth-app-exits.json"

var (
	recordAppExits = features.Android
	appExitFresh   = 30 * time.Minute
	appExitRetry   = 5 * time.Minute
	appExitKeep    = 30 * 24 * time.Hour
	appExitsPerApp = 50
	appExitSave    = 30 * time.Second
	appExitTimeout = 10 * time.Second
	appExitSources = []string{
		"https://www.cloudflare.com/cdn-cgi/trace",
		"https://api.ip.sb/geoip",
		"https://ipinfo.io/json",
	}
	lookupAppExit = lookupExitOf
)

var processNameRule = constant.ProcessName.String()

type AppExit struct {
	App     string `json:"app"`
	Node    string `json:"node"`
	Ip      string `json:"ip"`
	Country string `json:"country,omitempty"`
	First   int64  `json:"first"`
	Last    int64  `json:"last"`
}

type nodeExit struct {
	ip, country string
	at          time.Time
}

type appExitRecorder struct {
	mu      sync.Mutex
	writing sync.Mutex
	loaded  bool
	records []AppExit
	exits   map[string]nodeExit
	// The apps seen on a node whose exit is still being looked up.
	waiting map[string]map[string]int64
	saving  bool
}

var appExits = &appExitRecorder{}

func noteAppExit(tracker statistic.Tracker) {
	if !recordAppExits {
		return
	}
	info := tracker.Info()
	if info.Rule != processNameRule || len(info.Chain) == 0 {
		return
	}
	node := info.Chain[0]
	if node == "REJECT" || node == "REJECT-DROP" || node == guardOutbound {
		return
	}
	appExits.note(info.RulePayload, node, info.Start)
}

func (r *appExitRecorder) note(app, node string, at time.Time) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.load()
	if exit, known := r.exits[node]; known && at.Sub(exit.at) < exit.freshFor() {
		r.add(app, node, at.UnixMilli(), exit)
		return
	}
	apps, looking := r.waiting[node]
	if !looking {
		apps = map[string]int64{}
		r.waiting[node] = apps
		go func() {
			exit := lookupAppExit(node)
			purity.observe(node, exit.ip)
			r.settle(node, exit)
		}()
	}
	if _, seen := apps[app]; !seen {
		apps[app] = at.UnixMilli()
	}
}

func (e nodeExit) freshFor() time.Duration {
	if e.ip == "" {
		return appExitRetry
	}
	return appExitFresh
}

func (r *appExitRecorder) settle(node string, exit nodeExit) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.exits[node] = exit
	for app, at := range r.waiting[node] {
		r.add(app, node, at, exit)
	}
	delete(r.waiting, node)
}

func (r *appExitRecorder) load() {
	if r.loaded {
		return
	}
	r.loaded = true
	r.exits = map[string]nodeExit{}
	r.waiting = map[string]map[string]int64{}
	if buf, err := os.ReadFile(appExitsPath()); err == nil {
		_ = json.Unmarshal(buf, &r.records)
	}
}

// A record spans every use of one exit in a row; a new node or address
// starts the next.
func (r *appExitRecorder) add(app, node string, at int64, exit nodeExit) {
	if exit.ip == "" {
		return
	}
	for i := len(r.records) - 1; i >= 0; i-- {
		record := &r.records[i]
		if record.App != app {
			continue
		}
		if record.Node == node && record.Ip == exit.ip {
			if at > record.Last {
				record.Last = at
				r.scheduleSave()
			}
			return
		}
		break
	}
	r.records = append(r.records, AppExit{
		App:     app,
		Node:    node,
		Ip:      exit.ip,
		Country: exit.country,
		First:   at,
		Last:    at,
	})
	r.records = prunedAppExits(r.records, at-appExitKeep.Milliseconds())
	r.scheduleSave()
}

func prunedAppExits(records []AppExit, before int64) []AppExit {
	counts := map[string]int{}
	kept := make([]AppExit, 0, len(records))
	for i := len(records) - 1; i >= 0; i-- {
		record := records[i]
		if record.Last < before || counts[record.App] >= appExitsPerApp {
			continue
		}
		counts[record.App]++
		kept = append(kept, record)
	}
	for i, j := 0, len(kept)-1; i < j; i, j = i+1, j-1 {
		kept[i], kept[j] = kept[j], kept[i]
	}
	return kept
}

func (r *appExitRecorder) scheduleSave() {
	if r.saving {
		return
	}
	r.saving = true
	time.AfterFunc(appExitSave, r.save)
}

func (r *appExitRecorder) save() {
	r.writing.Lock()
	defer r.writing.Unlock()
	r.mu.Lock()
	r.saving = false
	buf, err := json.Marshal(r.records)
	r.mu.Unlock()
	if err != nil {
		return
	}
	path := appExitsPath()
	temporary := path + ".tmp"
	if os.WriteFile(temporary, buf, 0o600) == nil {
		_ = os.Rename(temporary, path)
	}
}

func appExitsPath() string {
	return filepath.Join(constant.Path.HomeDir(), appExitsFile)
}

func lookupExitOf(node string) nodeExit {
	exit := nodeExit{at: time.Now()}
	result := handleOutboundIp(&OutboundIpParams{
		ProxyName: node,
		Urls:      appExitSources,
		Timeout:   appExitTimeout.Milliseconds(),
	})
	if result.Error == "" {
		exit.ip, exit.country = parseExit(result.Body)
	}
	return exit
}

// Reads the JSON sources and Cloudflare's key=value trace alike.
func parseExit(body string) (string, string) {
	var fields struct {
		Ip          string `json:"ip"`
		CountryCode string `json:"country_code"`
		Country     string `json:"country"`
	}
	ip, country := "", ""
	if json.Unmarshal([]byte(body), &fields) == nil {
		ip, country = fields.Ip, fields.CountryCode
		if country == "" {
			country = fields.Country
		}
	} else {
		for _, line := range strings.Split(body, "\n") {
			key, value, _ := strings.Cut(strings.TrimSpace(line), "=")
			switch key {
			case "ip":
				ip = value
			case "loc":
				country = value
			}
		}
	}
	if _, err := netip.ParseAddr(ip); err != nil {
		return "", ""
	}
	if len(country) != 2 {
		country = ""
	}
	return ip, strings.ToUpper(country)
}
