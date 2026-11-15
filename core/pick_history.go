package core

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"time"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// The host reads this file itself, so the history outlives the Core and the
// app need not ask for it.
const pickHistoryFile = "sloth-history.jsonl"

// A due record is checked for this often; the clock behind a Go timer stands
// still while the phone sleeps, so the wall clock decides when one is due.
var (
	pickHistoryCheck   = 5 * time.Minute
	pickHistoryKeep    = 7 * 24 * time.Hour
	pickHistoryTimeout = 5 * time.Second
	pickHistoryURL     = defaultFastestURL
)

type pickSample struct {
	Time  int64  `json:"t"`
	Name  string `json:"n"`
	Delay uint16 `json:"d"`
}

type pickRecorder struct {
	mu       sync.Mutex
	group    string
	every    time.Duration
	started  bool
	recorded time.Time
	pruned   time.Time
}

var picks = &pickRecorder{}

// recordPicks names the group whose members are tested every [every]; an
// empty name pauses the record without losing it.
func (r *pickRecorder) recordPicks(group string, every time.Duration) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.group, r.every = group, every
	if group == "" || r.started {
		return
	}
	r.started = true
	r.recorded = lastPickSample(filepath.Join(constant.Path.HomeDir(), pickHistoryFile))
	go r.run()
}

// due names the group when a record is due at [now] and marks it taken.
func (r *pickRecorder) due(now time.Time) string {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.group == "" || now.Sub(r.recorded) < r.every {
		return ""
	}
	r.recorded = now
	return r.group
}

func (r *pickRecorder) run() {
	ticker := time.NewTicker(pickHistoryCheck)
	defer ticker.Stop()
	for {
		if !onFreeNetwork() {
			<-ticker.C
			continue
		}
		if name := r.due(time.Now()); name != "" {
			r.tick(name, time.Now())
		}
		<-ticker.C
	}
}

// Android leaves this file while it is on a network that costs nothing.
const unmeteredMarker = "sloth-unmetered"

var onFreeNetwork = func() bool {
	if runtime.GOOS != "android" {
		return true
	}
	_, err := os.Stat(filepath.Join(constant.Path.HomeDir(), unmeteredMarker))
	return err == nil
}

func (r *pickRecorder) tick(name string, now time.Time) {
	members := groupProxies(tunnel.Proxies()[name])
	if len(members) == 0 {
		return
	}
	samples := make([]pickSample, len(members))
	var wg sync.WaitGroup
	for i, member := range members {
		wg.Add(1)
		go func() {
			defer wg.Done()
			samples[i] = pickSample{Time: now.Unix(), Name: member.Name(), Delay: testPick(member)}
		}()
	}
	wg.Wait()
	path := filepath.Join(constant.Path.HomeDir(), pickHistoryFile)
	if err := appendPickSamples(path, samples); err != nil {
		logError("pick history write failed: %v", err)
		return
	}
	if now.Sub(r.pruned) > 12*time.Hour {
		r.pruned = now
		if err := prunePickHistory(path, now.Add(-pickHistoryKeep)); err != nil {
			logError("pick history prune failed: %v", err)
		}
	}
}

func groupProxies(proxy constant.Proxy) []constant.Proxy {
	if proxy == nil {
		return nil
	}
	group, ok := proxy.Adapter().(interface{ Proxies() []constant.Proxy })
	if !ok {
		return nil
	}
	return group.Proxies()
}

// A zero delay is a timeout, as in the host's own delay records.
func testPick(proxy constant.Proxy) uint16 {
	ctx, cancel := context.WithTimeout(context.Background(), pickHistoryTimeout)
	defer cancel()
	delay, err := proxy.URLTest(ctx, pickHistoryURL, anyDelayTestStatus)
	if err != nil {
		return 0
	}
	return delay
}

func appendPickSamples(path string, samples []pickSample) error {
	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)
	for _, sample := range samples {
		if err := encoder.Encode(sample); err != nil {
			return err
		}
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	if _, err := file.Write(buf.Bytes()); err != nil {
		_ = file.Close()
		return err
	}
	return file.Close()
}

func prunePickHistory(path string, before time.Time) error {
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	var kept bytes.Buffer
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		var sample pickSample
		if json.Unmarshal(scanner.Bytes(), &sample) != nil || sample.Time < before.Unix() {
			continue
		}
		kept.Write(scanner.Bytes())
		kept.WriteByte('\n')
	}
	_ = file.Close()
	if err := scanner.Err(); err != nil {
		return err
	}
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, kept.Bytes(), 0o600); err != nil {
		return err
	}
	return os.Rename(temporary, path)
}

func lastPickSample(path string) time.Time {
	file, err := os.Open(path)
	if err != nil {
		return time.Time{}
	}
	defer file.Close()
	var last int64
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		var sample pickSample
		if json.Unmarshal(scanner.Bytes(), &sample) == nil && sample.Time > last {
			last = sample.Time
		}
	}
	if last == 0 {
		return time.Time{}
	}
	return time.Unix(last, 0)
}
