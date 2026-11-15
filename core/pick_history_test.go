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
		fastestGroupKey: map[string]any{"name": "Picks", "type": "select", "proxies": []string{"a"}, "record": true},
	})
	recordedPicksGroup = ""
	t.Cleanup(func() { recordedPicksGroup = "" })

	if _, err := loadConfigWithBase(
		&SetupBase{Path: path, Overlay: overlay},
		filepath.Join(t.TempDir(), "config.yaml"),
	); err != nil {
		t.Fatalf("loadConfigWithBase = %v", err)
	}
	if recordedPicksGroup != "Picks" {
		t.Errorf("recorded group = %q, want Picks", recordedPicksGroup)
	}
}
