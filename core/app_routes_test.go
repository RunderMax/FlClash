package core

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
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

func TestAppPackagePatternTakesWindowsExecutables(t *testing.T) {
	for _, name := range []string{"com.example.chat", "chrome.exe", "ms-teams.exe", "Code - Insiders.exe", "1Password.exe"} {
		if !appPackagePattern.MatchString(name) {
			t.Errorf("%q should name an app", name)
		}
	}
	for _, name := range []string{"not,a.package", "chrome", " lead.exe", "line\nbreak.exe", "trail.exe "} {
		if appPackagePattern.MatchString(name) {
			t.Errorf("%q should not name an app", name)
		}
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

func TestAppRoutesOfKeepsTheRuleThatMatchesFirst(t *testing.T) {
	cfg, err := executor.ParseWithBytes([]byte(`proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
rules:
  - PROCESS-NAME,com.example.video,a
  - PROCESS-NAME,com.example.video,DIRECT
  - DOMAIN,example.com,DIRECT
  - MATCH,a
`))
	if err != nil {
		t.Fatalf("parse = %v", err)
	}

	if got := appRoutesOf(cfg.Rules); !reflect.DeepEqual(got, map[string]string{"com.example.video": "a"}) {
		t.Errorf("routes = %v, want the first rule of the app", got)
	}
}

func TestChangedAppsNamesEveryAppWhoseWayMoved(t *testing.T) {
	before := map[string]string{"com.a": "JP", "com.b": "US", "com.c": "DIRECT"}
	after := map[string]string{"com.a": "JP", "com.b": "SG", "com.d": "REJECT"}

	got := changedApps(before, after)

	want := map[string]bool{"com.b": true, "com.c": true, "com.d": true}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("changed = %v, want %v", got, want)
	}
}

func TestAppOfLooksUpAConnectionNoRuleLookedUp(t *testing.T) {
	previous := process.DefaultPackageNameResolver
	t.Cleanup(func() { process.DefaultPackageNameResolver = previous })
	process.DefaultPackageNameResolver = func(*constant.Metadata) (string, error) {
		return "com.looked.up", nil
	}

	if got := appOf(&constant.Metadata{Process: "com.known"}); got != "com.known" {
		t.Errorf("app = %q, want the recorded one", got)
	}
	if got := appOf(&constant.Metadata{}); got != "com.looked.up" {
		t.Errorf("app = %q, want the one looked up", got)
	}
}

func groupFields(t *testing.T, proxy constant.Proxy) (members []string, hidden bool) {
	t.Helper()
	buf, err := json.Marshal(proxy)
	if err != nil {
		t.Fatalf("marshal %s: %v", proxy.Name(), err)
	}
	var fields struct {
		All    []string `json:"all"`
		Hidden bool     `json:"hidden"`
	}
	if err := json.Unmarshal(buf, &fields); err != nil {
		t.Fatalf("unmarshal %s: %v", proxy.Name(), err)
	}
	return fields.All, fields.Hidden
}

func TestLoadConfigWithBaseGivesAnAppAGroupOfItsOwnPicks(t *testing.T) {
	path := writeBaseProfile(t, baseProfile)
	base, err := handleGetProfileBase(PathParams{Path: path})
	if err != nil {
		t.Fatalf("handleGetProfileBase = %v", err)
	}
	video, chat := appPickGroupPrefix+"com.example.video", appPickGroupPrefix+"com.example.chat"
	gone := appPickGroupPrefix + "com.example.gone"
	overlay := overlayOf(t, base, nil, map[string]any{
		appRoutesKey: map[string]any{
			"routes": map[string]any{
				"com.example.chat":  chat,
				"com.example.gone":  gone,
				"com.example.video": video,
				"com.example.web":   "a",
			},
			"picks": map[string]any{
				"com.example.chat":  map[string]any{"proxies": []string{"a"}, "auto": true},
				"com.example.gone":  map[string]any{"proxies": []string{"gone"}},
				"com.example.video": map[string]any{"proxies": []string{"b", "gone", "a", "b"}},
				"com.example.web":   map[string]any{"proxies": []string{"a"}},
			},
		},
	})

	cfg, err := loadConfigWithBase(&SetupBase{Path: path, Overlay: overlay}, filepath.Join(t.TempDir(), "config.yaml"))

	if err != nil {
		t.Fatalf("loadConfigWithBase = %v", err)
	}
	if group := cfg.Proxies[video]; group == nil || group.Type() != constant.Selector {
		t.Fatalf("video group = %v, want a select group", group)
	}
	if members, hidden := groupFields(t, cfg.Proxies[video]); !reflect.DeepEqual(members, []string{"b", "a"}) || !hidden {
		t.Errorf("video group = %v hidden %v, want [b a] hidden", members, hidden)
	}
	if group := cfg.Proxies[chat]; group == nil || group.Type() != constant.URLTest {
		t.Errorf("chat group = %v, want a url-test group", group)
	}
	for _, name := range []string{gone, appPickGroupPrefix + "com.example.web"} {
		if cfg.Proxies[name] != nil {
			t.Errorf("made %s, which no route takes or no member is left in", name)
		}
	}
	want := []string{
		"ProcessName,com.example.chat," + chat,
		"ProcessName,com.example.video," + video,
		"ProcessName,com.example.web,a",
	}
	if got := ruleLines(cfg); !reflect.DeepEqual(got[:len(want)], want) {
		t.Errorf("rules = %v, want %v first", got, want)
	}
}
