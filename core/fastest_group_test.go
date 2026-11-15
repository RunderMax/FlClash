package core

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/constant"
)

func groupMembers(t *testing.T, proxy constant.Proxy) []string {
	t.Helper()
	group, ok := proxy.Adapter().(constant.ProxyAdapter).(interface {
		Proxies() []constant.Proxy
	})
	if !ok {
		t.Fatalf("%s is not a group", proxy.Name())
	}
	names := []string{}
	for _, member := range group.Proxies() {
		names = append(names, member.Name())
	}
	return names
}

func TestLoadConfigWithBaseAddsTheFastestGroupOfTheProxiesItStillHas(t *testing.T) {
	path := writeBaseProfile(t, baseProfile)
	base, err := handleGetProfileBase(PathParams{Path: path})
	if err != nil {
		t.Fatalf("handleGetProfileBase = %v", err)
	}
	overlay := overlayOf(t, base, nil, map[string]any{
		fastestGroupKey: map[string]any{"name": "Fastest", "proxies": []string{"a", "gone", "b"}},
	})
	configPath := filepath.Join(t.TempDir(), "config.yaml")

	cfg, err := loadConfigWithBase(&SetupBase{Path: path, Overlay: overlay}, configPath)

	if err != nil {
		t.Fatalf("loadConfigWithBase = %v", err)
	}
	fastest := cfg.Proxies["Fastest"]
	if fastest == nil {
		t.Fatal("the fastest group is missing")
	}
	if fastest.Type() != constant.URLTest {
		t.Errorf("type = %v, want url-test", fastest.Type())
	}
	if got := groupMembers(t, fastest); !reflect.DeepEqual(got, []string{"a", "b"}) {
		t.Errorf("members = %v, want only the proxies the profile has", got)
	}
	if got := groupMembers(t, cfg.Proxies["g"]); !reflect.DeepEqual(got, []string{"a", "b", "Fastest"}) {
		t.Errorf("select group = %v, want the fastest group last", got)
	}
	written, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if strings.Contains(string(written), fastestGroupKey) {
		t.Error("the written config still carries the request")
	}
}

func TestLoadConfigWithBaseAddsASelectGroupWhenAskedForOne(t *testing.T) {
	path := writeBaseProfile(t, baseProfile)
	base, err := handleGetProfileBase(PathParams{Path: path})
	if err != nil {
		t.Fatalf("handleGetProfileBase = %v", err)
	}
	overlay := overlayOf(t, base, nil, map[string]any{
		fastestGroupKey: map[string]any{"name": "Picks", "type": "select", "proxies": []string{"b", "a"}},
	})

	cfg, err := loadConfigWithBase(
		&SetupBase{Path: path, Overlay: overlay},
		filepath.Join(t.TempDir(), "config.yaml"),
	)

	if err != nil {
		t.Fatalf("loadConfigWithBase = %v", err)
	}
	picks := cfg.Proxies["Picks"]
	if picks == nil || picks.Type() != constant.Selector {
		t.Fatalf("picks = %v, want a select group", picks)
	}
	if got := groupMembers(t, picks); !reflect.DeepEqual(got, []string{"b", "a"}) {
		t.Errorf("members = %v, want the chosen order", got)
	}
}

func TestLoadConfigWithBaseAddsNoGroupWhenNoChosenProxyIsLeft(t *testing.T) {
	path := writeBaseProfile(t, baseProfile)
	base, err := handleGetProfileBase(PathParams{Path: path})
	if err != nil {
		t.Fatalf("handleGetProfileBase = %v", err)
	}
	overlay := overlayOf(t, base, nil, map[string]any{
		fastestGroupKey: map[string]any{"name": "Fastest", "proxies": []string{"gone"}},
	})

	cfg, err := loadConfigWithBase(
		&SetupBase{Path: path, Overlay: overlay},
		filepath.Join(t.TempDir(), "config.yaml"),
	)

	if err != nil {
		t.Fatalf("loadConfigWithBase = %v", err)
	}
	if cfg.Proxies["Fastest"] != nil {
		t.Error("a group with no proxies was added")
	}
	if got := groupMembers(t, cfg.Proxies["g"]); !reflect.DeepEqual(got, []string{"a", "b"}) {
		t.Errorf("select group = %v, want it untouched", got)
	}
}

func TestLoadSetupConfigAddsTheFastestGroupWithoutABase(t *testing.T) {
	home := t.TempDir()
	previous := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() { constant.SetHomeDir(previous) })
	profile := `proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
proxy-groups:
  - {name: g, type: select, proxies: [a]}
rules:
  - MATCH,g
x-sloth-fastest: {name: Fastest, proxies: [a]}
`
	path := filepath.Join(home, "config.yaml")
	if err := os.WriteFile(path, []byte(profile), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	cfg, err := loadSetupConfig(&SetupParams{})

	if err != nil {
		t.Fatalf("loadSetupConfig = %v", err)
	}
	if cfg.Proxies["Fastest"] == nil {
		t.Fatal("the fastest group is missing")
	}
	written, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if strings.Contains(string(written), fastestGroupKey) {
		t.Error("config.yaml still carries the request")
	}
}
