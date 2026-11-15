package core

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
)

func ruleLines(cfg *config.Config) []string {
	lines := make([]string, 0, len(cfg.Rules))
	for _, rule := range cfg.Rules {
		lines = append(lines, rule.RuleType().String()+","+rule.Payload()+","+rule.Adapter())
	}
	return lines
}

func TestLoadConfigWithBaseRoutesAppsAfterTheLeadingRules(t *testing.T) {
	path := writeBaseProfile(t, baseProfile)
	base, err := handleGetProfileBase(PathParams{Path: path})
	if err != nil {
		t.Fatalf("handleGetProfileBase = %v", err)
	}
	overlay := overlayOf(t, base, []string{"DST-PORT,9,REJECT", "DOMAIN,added.example,DIRECT"}, map[string]any{
		appRoutesKey: map[string]any{
			"at": 1,
			"routes": map[string]any{
				"com.example.chat":  "b",
				"com.example.gone":  "gone",
				"com.example.video": "g",
				"com.example.web":   "DIRECT",
				"not,a.package":     "a",
			},
		},
	})
	configPath := filepath.Join(t.TempDir(), "config.yaml")

	cfg, err := loadConfigWithBase(&SetupBase{Path: path, Overlay: overlay}, configPath)

	if err != nil {
		t.Fatalf("loadConfigWithBase = %v", err)
	}
	want := []string{
		"DstPort,9,REJECT",
		"ProcessName,com.example.chat,b",
		"ProcessName,com.example.video,g",
		"ProcessName,com.example.web,DIRECT",
		"Domain,added.example,DIRECT",
		"DomainSuffix,example.com,g",
	}
	if got := ruleLines(cfg); !reflect.DeepEqual(got[:len(want)], want) {
		t.Errorf("rules = %v, want %v first", got, want)
	}
	written, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if strings.Contains(string(written), appRoutesKey) {
		t.Error("the written config still carries the request")
	}
}

func TestLoadConfigWithBaseRoutesAnAppToThePicksGroup(t *testing.T) {
	path := writeBaseProfile(t, baseProfile)
	base, err := handleGetProfileBase(PathParams{Path: path})
	if err != nil {
		t.Fatalf("handleGetProfileBase = %v", err)
	}
	overlay := overlayOf(t, base, nil, map[string]any{
		fastestGroupKey: map[string]any{"name": "Picks", "type": "select", "proxies": []string{"a"}},
		appRoutesKey:    map[string]any{"routes": map[string]any{"com.example.video": "Picks"}},
	})

	cfg, err := loadConfigWithBase(
		&SetupBase{Path: path, Overlay: overlay},
		filepath.Join(t.TempDir(), "config.yaml"),
	)

	if err != nil {
		t.Fatalf("loadConfigWithBase = %v", err)
	}
	if got := ruleLines(cfg); len(got) == 0 || got[0] != "ProcessName,com.example.video,Picks" {
		t.Errorf("rules = %v, want the route to the picks group first", got)
	}
}

func TestLoadSetupConfigRoutesAppsWithoutABase(t *testing.T) {
	home := t.TempDir()
	previous := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() { constant.SetHomeDir(previous) })
	profile := `proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
proxy-groups:
  - {name: g, type: select, proxies: [a]}
rules:
  - DST-PORT,9,REJECT
  - MATCH,g
x-sloth-app-routes: {at: 1, routes: {com.example.video: a, com.example.gone: gone}}
`
	path := filepath.Join(home, "config.yaml")
	if err := os.WriteFile(path, []byte(profile), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	cfg, err := loadSetupConfig(&SetupParams{})

	if err != nil {
		t.Fatalf("loadSetupConfig = %v", err)
	}
	want := []string{"DstPort,9,REJECT", "ProcessName,com.example.video,a", "Match,,g"}
	if got := ruleLines(cfg); !reflect.DeepEqual(got, want) {
		t.Errorf("rules = %v, want %v", got, want)
	}
	written, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if strings.Contains(string(written), appRoutesKey) {
		t.Error("config.yaml still carries the request")
	}
}
