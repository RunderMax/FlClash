package core

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
	"go.yaml.in/yaml/v3"
)

func socksNode(t *testing.T, name string) constant.Proxy {
	t.Helper()
	proxy, err := adapter.ParseProxy(map[string]any{"name": name, "type": "socks5", "server": "127.0.0.1", "port": 1080})
	if err != nil {
		t.Fatalf("ParseProxy(%s) = %v", name, err)
	}
	return proxy
}

// useGuardedTunnel puts a clean node, a hosting one, an unchecked one and a
// group over the hosting one in the tunnel, guarded by [state].
func useGuardedTunnel(t *testing.T, state *guardState) *testPurity {
	t.Helper()
	keepTunnel(t)
	test := useTestPurity(t)
	dirty := socksNode(t, "dirty")
	tunnel.UpdateProxies(map[string]constant.Proxy{
		"clean":   socksNode(t, "clean"),
		"dirty":   dirty,
		"unknown": socksNode(t, "unknown"),
		"g":       selectorOver(t, "g", dirty),
		"DIRECT":  namedProxy("DIRECT"),
	}, nil)
	test.know("clean", "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	test.know("dirty", "2.2.2.2", time.Minute, ipVerdict{Type: "hosting"})
	previous := currentGuard.Load()
	currentGuard.Store(state)
	t.Cleanup(func() { currentGuard.Store(previous) })
	return test
}

func TestReadGuardRequestLeavesTheRequestInTheConfig(t *testing.T) {
	var document yaml.Node
	if err := yaml.Unmarshal([]byte("x-sloth-guard: {all: true, apps: [com.example.chat]}\nmode: rule\n"), &document); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	root := document.Content[0]

	readGuardRequest(root)

	want := guardRequest{All: true, Apps: []string{"com.example.chat"}}
	if !reflect.DeepEqual(loadedGuard, want) {
		t.Errorf("request = %+v, want %+v", loadedGuard, want)
	}
	if mappingValue(root, guardKey) == nil {
		t.Error("the request was taken out of the config")
	}
	t.Cleanup(func() { loadedGuard = guardRequest{} })
}

func TestNewGuardStateGuardsNothingWithoutASwitchOn(t *testing.T) {
	if state := newGuardState(guardRequest{Apps: []string{"not a package"}}); state != nil {
		t.Errorf("state = %+v, want none", state)
	}
	state := newGuardState(guardRequest{Apps: []string{"com.example.chat", "not a package"}})
	if state == nil || state.all || !reflect.DeepEqual(state.apps, map[string]bool{"com.example.chat": true}) {
		t.Errorf("state = %+v, want only the app", state)
	}
}

func TestLoadSetupConfigKeepsTheGuardForTheNextLoad(t *testing.T) {
	home := t.TempDir()
	previous := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() {
		constant.SetHomeDir(previous)
		loadedGuard = guardRequest{}
	})
	profile := `proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
rules:
  - MATCH,a
x-sloth-guard: {all: true}
`
	path := filepath.Join(home, "config.yaml")
	if err := os.WriteFile(path, []byte(profile), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	for range 2 {
		if _, err := loadSetupConfig(&SetupParams{}); err != nil {
			t.Fatalf("loadSetupConfig = %v", err)
		}
		if !loadedGuard.All {
			t.Fatal("the guard was lost on a load")
		}
	}
	written, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if !strings.Contains(string(written), guardKey) {
		t.Error("config.yaml lost the request the service loads again")
	}
}

func TestArmGuardWrapsEveryRuleAndAddsTheGuardOutbound(t *testing.T) {
	cfg, err := executor.ParseWithBytes([]byte(`proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
sub-rules:
  sub: ["MATCH,a"]
rules:
  - DOMAIN,example.com,a
  - MATCH,DIRECT
`))
	if err != nil {
		t.Fatalf("parse = %v", err)
	}

	armGuard(cfg)

	if guard := cfg.Proxies[guardOutbound]; guard == nil || guard.Type() != constant.Reject {
		t.Fatalf("guard outbound = %v, want a reject", guard)
	}
	for _, rule := range cfg.Rules {
		if _, ok := rule.(*guardedRuleWrapper); !ok {
			t.Errorf("rule %s,%s is %T, want it guarded and still a mihomo wrapper", rule.RuleType(), rule.Payload(), rule)
		}
	}
	if rule := cfg.SubRules["sub"][0]; reflect.TypeOf(rule) != reflect.TypeFor[*guardedRule]() {
		t.Errorf("sub-rule is %T, want it guarded", rule)
	}
	if got := ruleLines(cfg); !reflect.DeepEqual(got, []string{"Domain,example.com,a", "Match,,DIRECT"}) {
		t.Errorf("rules = %v, want them unchanged in what they say", got)
	}
}

func TestGuardRouteStopsEveryNodeThatIsNotKnownClean(t *testing.T) {
	test := useGuardedTunnel(t, &guardState{all: true})
	metadata := &constant.Metadata{}
	cases := map[string]string{
		"clean":   "clean",
		"dirty":   guardOutbound,
		"g":       guardOutbound,
		"unknown": guardOutbound,
		"DIRECT":  "DIRECT",
		"missing": "missing",
	}
	for name, want := range cases {
		if got := guardRoute(metadata, constant.RuleMatchHelper{}, name); got != want {
			t.Errorf("guardRoute(%s) = %s, want %s", name, got, want)
		}
	}
	test.settle(t)
	if test.askedFor("unknown") != 1 {
		t.Error("an unchecked node was not checked")
	}
}

func TestGuardRouteLooksUpTheAppOnlyForAnUncleanNode(t *testing.T) {
	useGuardedTunnel(t, &guardState{apps: map[string]bool{"com.guarded": true}})
	lookups := 0
	route := func(app, name string) string {
		metadata := &constant.Metadata{}
		helper := constant.RuleMatchHelper{FindProcess: func() {
			lookups++
			metadata.Process = app
		}}
		return guardRoute(metadata, helper, name)
	}

	if got := route("com.guarded", "dirty"); got != guardOutbound {
		t.Errorf("guarded app through dirty = %s, want the guard", got)
	}
	if got := route("com.other", "dirty"); got != "dirty" {
		t.Errorf("other app through dirty = %s, want it left alone", got)
	}
	if got := route("com.guarded", "clean"); got != "clean" {
		t.Errorf("guarded app through clean = %s, want it let through", got)
	}
	if lookups != 2 {
		t.Errorf("looked the app up %d times, want only for the dirty node", lookups)
	}
}

func TestBlockedByGuardJudgesTheNodeAConnectionLeftThrough(t *testing.T) {
	useGuardedTunnel(t, &guardState{apps: map[string]bool{"com.guarded": true}})
	state := currentGuard.Load()
	info := func(app string, chain ...string) *statistic.TrackerInfo {
		return &statistic.TrackerInfo{Chain: chain, Metadata: &constant.Metadata{Process: app}}
	}

	if !blockedByGuard(state, info("com.guarded", "dirty", "g")) {
		t.Error("a guarded app left through a dirty node unblocked")
	}
	for _, unblocked := range []*statistic.TrackerInfo{
		info("com.other", "dirty", "g"),
		info("com.guarded", "clean"),
		info("com.guarded", guardOutbound),
		info("com.guarded", "DIRECT"),
		info("com.guarded"),
	} {
		if blockedByGuard(state, unblocked) {
			t.Errorf("blocked %v of %s", unblocked.Chain, unblocked.Metadata.Process)
		}
	}
}
