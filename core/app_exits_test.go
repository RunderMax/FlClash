package core

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
)

func TestParseExitReadsEachSource(t *testing.T) {
	cases := []struct {
		body, ip, country string
	}{
		{"fl=1\nip=1.2.3.4\nloc=JP\n", "1.2.3.4", "JP"},
		{`{"ip":"5.6.7.8","country":"United States","country_code":"US"}`, "5.6.7.8", "US"},
		{`{"ip":"2001:db8::1","country":"sg"}`, "2001:db8::1", "SG"},
		{`{"ip":"not an address","country":"JP"}`, "", ""},
		{"<html>rate limited</html>", "", ""},
	}
	for _, c := range cases {
		if ip, country := parseExit(c.body); ip != c.ip || country != c.country {
			t.Errorf("parseExit(%q) = %q, %q, want %q, %q", c.body, ip, country, c.ip, c.country)
		}
	}
}

func useTestAppExits(t *testing.T, exits map[string]string) *appExitRecorder {
	t.Helper()
	home := t.TempDir()
	previousHome := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	previousLookup, previousSave := lookupAppExit, appExitSave
	lookupAppExit = func(node string) nodeExit {
		return nodeExit{ip: exits[node], country: "JP", at: time.Now()}
	}
	appExitSave = 10 * time.Millisecond
	r := &appExitRecorder{}
	t.Cleanup(func() {
		flushAppExits(t, r)
		constant.SetHomeDir(previousHome)
		lookupAppExit, appExitSave = previousLookup, previousSave
	})
	return r
}

// A save still pending would write into the next test's home.
func flushAppExits(t *testing.T, r *appExitRecorder) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for {
		r.mu.Lock()
		saving := r.saving
		r.mu.Unlock()
		if !saving {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the record was never saved")
		}
		time.Sleep(time.Millisecond)
	}
	r.writing.Lock()
	defer r.writing.Unlock()
}

func noteSettled(t *testing.T, r *appExitRecorder, app, node string, at time.Time) {
	t.Helper()
	r.note(app, node, at)
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		r.mu.Lock()
		waiting := len(r.waiting)
		r.mu.Unlock()
		if waiting == 0 {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("the exit lookup never settled")
}

func TestAppExitRecorderJoinsUsesOfOneExitAndStartsAnotherOnChange(t *testing.T) {
	r := useTestAppExits(t, map[string]string{"JP-01": "1.1.1.1", "US-01": "2.2.2.2"})
	start := time.Now()
	at := func(minutes int) time.Time { return start.Add(time.Duration(minutes) * time.Minute) }

	noteSettled(t, r, "com.example.video", "JP-01", at(0))
	noteSettled(t, r, "com.example.video", "JP-01", at(1))
	noteSettled(t, r, "com.example.video", "US-01", at(2))
	noteSettled(t, r, "com.example.chat", "US-01", at(2))
	noteSettled(t, r, "com.example.video", "JP-01", at(3))

	type use struct {
		app, node, ip string
		first, last   int64
	}
	var got []use
	for _, record := range r.records {
		got = append(got, use{record.App, record.Node, record.Ip, record.First, record.Last})
	}
	ms := func(minutes int) int64 { return at(minutes).UnixMilli() }
	want := []use{
		{"com.example.video", "JP-01", "1.1.1.1", ms(0), ms(1)},
		{"com.example.video", "US-01", "2.2.2.2", ms(2), ms(2)},
		{"com.example.chat", "US-01", "2.2.2.2", ms(2), ms(2)},
		{"com.example.video", "JP-01", "1.1.1.1", ms(3), ms(3)},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("records = %v, want %v", got, want)
	}
}

func TestAppExitRecorderKeepsNoRecordOfAFailedLookup(t *testing.T) {
	r := useTestAppExits(t, map[string]string{})

	noteSettled(t, r, "com.example.video", "JP-01", time.Now())

	if len(r.records) != 0 {
		t.Errorf("records = %v, want none without an address", r.records)
	}
}

func TestAppExitRecorderSavesWhatTheNextOneLoads(t *testing.T) {
	r := useTestAppExits(t, map[string]string{"JP-01": "1.1.1.1"})

	noteSettled(t, r, "com.example.video", "JP-01", time.Now())
	deadline := time.Now().Add(time.Second)
	var saved []AppExit
	for time.Now().Before(deadline) {
		if buf, err := os.ReadFile(appExitsPath()); err == nil && json.Unmarshal(buf, &saved) == nil {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}

	if len(saved) != 1 || saved[0].Ip != "1.1.1.1" || saved[0].Country != "JP" {
		t.Fatalf("saved = %v, want the record", saved)
	}
	next := &appExitRecorder{}
	next.mu.Lock()
	next.load()
	next.mu.Unlock()
	if !reflect.DeepEqual(next.records, saved) {
		t.Errorf("loaded = %v, want %v", next.records, saved)
	}
}

func TestPrunedAppExitsKeepsTheNewestOfEachApp(t *testing.T) {
	previous := appExitsPerApp
	appExitsPerApp = 2
	t.Cleanup(func() { appExitsPerApp = previous })
	records := []AppExit{
		{App: "a", Ip: "1", Last: 10},
		{App: "a", Ip: "2", Last: 20},
		{App: "b", Ip: "3", Last: 5},
		{App: "a", Ip: "4", Last: 30},
		{App: "b", Ip: "5", Last: 40},
	}

	got := prunedAppExits(records, 8)

	want := []AppExit{
		{App: "a", Ip: "2", Last: 20},
		{App: "a", Ip: "4", Last: 30},
		{App: "b", Ip: "5", Last: 40},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("pruned = %v, want %v", got, want)
	}
}
