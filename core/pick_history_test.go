package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPickHistoryAppendsAndPrunesOldSamples(t *testing.T) {
	path := filepath.Join(t.TempDir(), pickHistoryFile)
	now := time.Unix(1_800_000_000, 0)
	old := now.Add(-8 * 24 * time.Hour)

	if err := appendPickSamples(path, []pickSample{{Time: old.Unix(), Name: "a", Delay: 90}}); err != nil {
		t.Fatalf("append old = %v", err)
	}
	if err := appendPickSamples(path, []pickSample{
		{Time: now.Unix(), Name: "a", Delay: 120},
		{Time: now.Unix(), Name: "b", Delay: 0},
	}); err != nil {
		t.Fatalf("append = %v", err)
	}
	if err := prunePickHistory(path, now.Add(-pickHistoryKeep)); err != nil {
		t.Fatalf("prune = %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read = %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	want := []string{
		`{"t":1800000000,"n":"a","d":120}`,
		`{"t":1800000000,"n":"b","d":0}`,
	}
	if strings.Join(lines, "|") != strings.Join(want, "|") {
		t.Errorf("history = %v, want %v", lines, want)
	}
}

func TestPruningAMissingHistoryIsNoError(t *testing.T) {
	if err := prunePickHistory(filepath.Join(t.TempDir(), "none.jsonl"), time.Now()); err != nil {
		t.Errorf("prune = %v", err)
	}
}

func TestLoadConfigWithBaseNamesTheGroupToRecord(t *testing.T) {
	path := writeBaseProfile(t, baseProfile)
	base, err := handleGetProfileBase(PathParams{Path: path})
	if err != nil {
		t.Fatalf("handleGetProfileBase = %v", err)
	}
	overlay := overlayOf(t, base, nil, map[string]any{
		fastestGroupKey: map[string]any{"name": "Picks", "type": "select", "proxies": []string{"a"}, "record": 180},
	})
	recordedPicksGroup, recordedPicksEvery = "", 0
	t.Cleanup(func() { recordedPicksGroup, recordedPicksEvery = "", 0 })

	if _, err := loadConfigWithBase(
		&SetupBase{Path: path, Overlay: overlay},
		filepath.Join(t.TempDir(), "config.yaml"),
	); err != nil {
		t.Fatalf("loadConfigWithBase = %v", err)
	}
	if recordedPicksGroup != "Picks" || recordedPicksEvery != 3*time.Hour {
		t.Errorf("recorded = %q every %v, want Picks every 3h", recordedPicksGroup, recordedPicksEvery)
	}
}

func TestARecordIsDueOnlyOnceItsIntervalHasPassed(t *testing.T) {
	start := time.Unix(1_800_000_000, 0)
	r := &pickRecorder{group: "Picks", every: 3 * time.Hour, recorded: start}

	if got := r.due(start.Add(2 * time.Hour)); got != "" {
		t.Errorf("due after 2h = %q, want nothing", got)
	}
	if got := r.due(start.Add(3 * time.Hour)); got != "Picks" {
		t.Errorf("due after 3h = %q, want Picks", got)
	}
	if got := r.due(start.Add(3*time.Hour + time.Minute)); got != "" {
		t.Errorf("due right after a record = %q, want nothing", got)
	}
}

func TestTheLastSampleIsReadBackFromTheHistory(t *testing.T) {
	path := filepath.Join(t.TempDir(), pickHistoryFile)
	if err := appendPickSamples(path, []pickSample{{Time: 100, Name: "a"}, {Time: 300, Name: "b"}}); err != nil {
		t.Fatalf("append = %v", err)
	}
	if got := lastPickSample(path); got.Unix() != 300 {
		t.Errorf("last = %v, want 300", got.Unix())
	}
	if got := lastPickSample(filepath.Join(t.TempDir(), "none")); !got.IsZero() {
		t.Errorf("last of nothing = %v, want zero", got)
	}
}
