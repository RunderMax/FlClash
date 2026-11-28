package core

import (
	"context"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/tunnel"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
)

// Only what steering reads; anything else would panic on the nil embed.
type stubMember struct {
	constant.Proxy
	name  string
	kind  constant.AdapterType
	delay uint16
	dead  bool
}

func (m stubMember) Name() string                      { return m.name }
func (m stubMember) Type() constant.AdapterType        { return m.kind }
func (m stubMember) AliveForTestUrl(string) bool       { return !m.dead }
func (m stubMember) LastDelayForTestUrl(string) uint16 { return m.delay }

func members(list ...stubMember) []constant.Proxy {
	proxies := make([]constant.Proxy, len(list))
	for i, member := range list {
		proxies[i] = member
	}
	return proxies
}

func useCountries(t *testing.T, countries map[string]string) {
	t.Helper()
	previous := countryOf
	countryOf = func(ip string) string { return countries[ip] }
	t.Cleanup(func() { countryOf = previous })
}

func TestNextPickStartsOnTheFirstCleanLiveMember(t *testing.T) {
	test := useTestPurity(t)
	for node, kind := range map[string]string{"slow": "residential", "fast": "mobile", "dc": "hosting", "dead": "business"} {
		test.know(node, node+"-ip", time.Minute, ipVerdict{Type: kind})
	}
	group := members(
		stubMember{name: "slow", delay: 300},
		stubMember{name: "fast", delay: 100},
		stubMember{name: "dc", delay: 20},
		stubMember{name: "dead", delay: 10, dead: true},
	)

	if got := nextPick(group, "", "", 0, nil, purityGood); got != "slow" {
		t.Errorf("picked %q, want the first clean one, the main line", got)
	}
	if got := nextPick(members(stubMember{name: "dc"}), "", "", 0, nil, purityGood); got != "" {
		t.Errorf("picked %q, want the choice left to url-test", got)
	}
}

func TestNextPickKeepsTheOneInUseThroughABriefOutage(t *testing.T) {
	test := useTestPurity(t)
	useCountries(t, map[string]string{"1.1.1.1": "US", "2.2.2.2": "US"})
	test.know("a", "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	test.know("b", "2.2.2.2", time.Minute, ipVerdict{Type: "residential"})

	slow := members(stubMember{name: "a", delay: 900}, stubMember{name: "b", delay: 10})
	if got := nextPick(slow, "", "a", 0, nil, purityGood); got != "a" {
		t.Errorf("picked %q, want the one in use kept however slow", got)
	}
	dead := members(stubMember{name: "a", dead: true}, stubMember{name: "b", delay: 10})
	if got := nextPick(dead, "", "a", leaveDeadAfter-time.Second, nil, purityGood); got != "a" {
		t.Errorf("picked %q, want no move on a brief outage", got)
	}
	if got := nextPick(dead, "", "a", leaveDeadAfter, nil, purityGood); got != "b" {
		t.Errorf("picked %q, want the move once it stayed dead", got)
	}
}

func TestNextPickMovesOnlyWithinTheCountry(t *testing.T) {
	test := useTestPurity(t)
	useCountries(t, map[string]string{"1.1.1.1": "US", "2.2.2.2": "US", "3.3.3.3": "JP", "4.4.4.4": "US"})
	test.know("a", "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	test.know("same", "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	test.know("us", "2.2.2.2", time.Minute, ipVerdict{Type: "residential"})
	test.know("jp", "3.3.3.3", time.Minute, ipVerdict{Type: "residential"})
	test.know("dc", "4.4.4.4", time.Minute, ipVerdict{Type: "hosting"})
	down := stubMember{name: "a", dead: true}

	all := members(down, stubMember{name: "same", delay: 500}, stubMember{name: "us", delay: 50}, stubMember{name: "jp", delay: 5})
	if got := nextPick(all, "", "a", leaveDeadAfter, nil, purityGood); got != "same" {
		t.Errorf("picked %q, want the member on the same address first", got)
	}
	abroad := members(down, stubMember{name: "us", delay: 50}, stubMember{name: "jp", delay: 5}, stubMember{name: "dc", delay: 1})
	if got := nextPick(abroad, "", "a", leaveDeadAfter, nil, purityGood); got != "us" {
		t.Errorf("picked %q, want the clean member in the same country", got)
	}
	if got := nextPick(members(down, stubMember{name: "jp", delay: 5}), "", "a", leaveDeadAfter, nil, purityGood); got != "a" {
		t.Errorf("picked %q, want it to stay with none in the country", got)
	}
	unclean := members(stubMember{name: "dc", delay: 1}, stubMember{name: "us", delay: 50})
	if got := nextPick(unclean, "", "dc", 0, nil, purityGood); got != "us" {
		t.Errorf("picked %q, want the unclean member left at once", got)
	}
}

func TestNextPickTakesTheStandInsInTheirOrder(t *testing.T) {
	test := useTestPurity(t)
	useCountries(t, map[string]string{"1.1.1.1": "MY"})
	for _, node := range []string{"main", "b1", "b2", "b3"} {
		test.know(node, "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	}
	group := members(
		stubMember{name: "main", dead: true},
		stubMember{name: "b1", dead: true},
		stubMember{name: "b2", delay: 900},
		stubMember{name: "b3", delay: 10},
	)

	if got := nextPick(group, "", "main", leaveDeadAfter, nil, purityGood); got != "b2" {
		t.Errorf("picked %q, want the first stand-in that is up, however slow", got)
	}
}

func TestNextPickReturnsToAnEarlierLineOnceItHasStayedUp(t *testing.T) {
	test := useTestPurity(t)
	useCountries(t, map[string]string{"1.1.1.1": "MY", "9.9.9.9": "US"})
	for _, node := range []string{"main", "b1", "b2"} {
		test.know(node, "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	}
	test.know("abroad", "9.9.9.9", time.Minute, ipVerdict{Type: "residential"})
	group := members(stubMember{name: "abroad"}, stubMember{name: "main"}, stubMember{name: "b1"}, stubMember{name: "b2"})
	long := returnAfter

	if got := nextPick(group, "", "b2", 0, map[string]time.Duration{"main": long - time.Second, "b1": time.Minute}, purityGood); got != "b2" {
		t.Errorf("picked %q, want no return to a line only just back", got)
	}
	if got := nextPick(group, "", "b2", 0, map[string]time.Duration{"main": time.Minute, "b1": long}, purityGood); got != "b1" {
		t.Errorf("picked %q, want the earliest line that has stayed up", got)
	}
	if got := nextPick(group, "", "b2", 0, map[string]time.Duration{"abroad": long, "main": long, "b1": long}, purityGood); got != "main" {
		t.Errorf("picked %q, want the main line, not one abroad", got)
	}
	if got := nextPick(group, "", "main", 0, map[string]time.Duration{"b1": long, "b2": long}, purityGood); got != "main" {
		t.Errorf("picked %q, want the main line kept over the ones after it", got)
	}
}

func TestAutoPickGroupsFindsTheHostsUrlTestGroups(t *testing.T) {
	proxies := map[string]constant.Proxy{
		slothPickGroup:                       stubMember{kind: constant.URLTest},
		appPickGroupPrefix + "com.example.a": stubMember{kind: constant.URLTest},
		appPickGroupPrefix + "com.example.b": stubMember{kind: constant.Selector},
		"Auto":                               stubMember{kind: constant.URLTest},
	}

	want := []string{slothPickGroup, appPickGroupPrefix + "com.example.a"}
	if got := autoPickGroups(proxies); !reflect.DeepEqual(got, want) {
		t.Errorf("groups = %v, want %v", got, want)
	}
}

func TestNextPickChecksAMemberNotYetKnown(t *testing.T) {
	test := useTestPurity(t)

	got := nextPick(members(stubMember{name: "x", delay: math.MaxUint16}), "", "", 0, nil, purityGood)

	if got != "" {
		t.Errorf("picked %q, want none", got)
	}
	test.settle(t)
	if test.askedFor("x") != 1 {
		t.Error("an unchecked member was not checked")
	}
}

func TestNextPickTakesNormalNodesWhereTheFloorAllows(t *testing.T) {
	test := useTestPurity(t)
	useCountries(t, map[string]string{"1.1.1.1": "US", "2.2.2.2": "US"})
	test.know("dc1", "1.1.1.1", time.Minute, ipVerdict{Type: "hosting"})
	test.know("dc2", "2.2.2.2", time.Minute, ipVerdict{Type: "hosting"})
	test.know("home", "3.3.3.3", time.Minute, ipVerdict{Type: "residential"})
	group := members(stubMember{name: "dc1"}, stubMember{name: "dc2"}, stubMember{name: "home"})

	if got := nextPick(group, "", "", 0, nil, purityNormal); got != "home" {
		t.Errorf("started on %q, want a good node ahead of the normal ones", got)
	}
	if got := nextPick(group[:2], "", "", 0, nil, purityNormal); got != "dc1" {
		t.Errorf("started on %q, want the first normal node with no good one", got)
	}
	if got := nextPick(group[:2], "", "", 0, nil, purityGood); got != "" {
		t.Errorf("started on %q, want none under a good floor", got)
	}
	if got := nextPick(group[:2], "", "dc1", 0, nil, purityNormal); got != "dc1" {
		t.Errorf("picked %q, want the normal node in use kept", got)
	}
	down := members(stubMember{name: "dc1", dead: true}, stubMember{name: "dc2"})
	if got := nextPick(down, "", "dc1", leaveDeadAfter, nil, purityNormal); got != "dc2" {
		t.Errorf("picked %q, want the normal stand-in", got)
	}
}

func TestSteerMovesTheLineAndLeavesTheUrlTestGroupOnIt(t *testing.T) {
	keepTunnel(t)
	home := t.TempDir()
	previous := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() { constant.SetHomeDir(previous) })
	profile := `proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
  - {name: b, type: socks5, server: 127.0.0.1, port: 1081}
proxy-groups:
  - {name: g, type: select, proxies: [a]}
rules:
  - MATCH,g
x-sloth-fastest: {name: Sloth Pick, type: url-test, proxies: [a, b]}
`
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(profile), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}
	cfg, err := loadSetupConfig(&SetupParams{})
	if err != nil {
		t.Fatalf("loadSetupConfig = %v", err)
	}
	tunnel.UpdateProxies(cfg.Proxies, cfg.Providers)
	test := useTestPurity(t)
	useCountries(t, map[string]string{"1.1.1.1": "MY"})
	test.know("a", "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	test.know("b", "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	alive := map[string]bool{"a": true, "b": true}
	previousTest := testMembers
	testMembers = func(members []constant.Proxy, url string) {
		for _, member := range members {
			status := 204
			if !alive[member.Name()] {
				status = 500
			}
			server := probeServer(t, func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(status) })
			_, _ = member.URLTest(context.Background(), server.URL, steerTestStatus("/generate_204"))
			_ = url
		}
	}
	t.Cleanup(func() { testMembers = previousTest })

	s := &steerer{poke: make(chan struct{}, 1), started: true}
	s.reset(cfg.Proxies)
	if !reflect.DeepEqual(s.groups, []string{slothPickGroup}) {
		t.Fatalf("groups = %v, want the picks group", s.groups)
	}
	line, members := lineMembers(slothPickGroup)
	if line == nil || len(members) != 2 {
		t.Fatalf("line = %v with %d members, want both nodes", line, len(members))
	}
	s.steer()
	if got := line.Now(); got != "a" {
		t.Errorf("line on %q, want the main line", got)
	}
	if got := finalNode(cfg.Proxies[slothPickGroup], &constant.Metadata{}).Name(); got != "a" {
		t.Errorf("the picks group leads to %q, want the line's node", got)
	}

	alive["a"] = false
	s.tested = map[string]time.Time{}
	s.steer()
	if members[0].AliveForTestUrl(urlTestURL(mustURLTest(t, cfg.Proxies[slothPickGroup]))) {
		t.Fatal("the main line still counts as up after a failed check")
	}
	if got := finalNode(cfg.Proxies[slothPickGroup], &constant.Metadata{}).Name(); got != "a" {
		t.Errorf("one failed check moved traffic to %q, want it kept on the main line", got)
	}
}

func mustURLTest(t *testing.T, proxy constant.Proxy) *outboundgroup.URLTest {
	t.Helper()
	group, ok := adapterAs[*outboundgroup.URLTest](proxy)
	if !ok {
		t.Fatal("not a url-test group")
	}
	return group
}
