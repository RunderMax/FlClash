package core

import (
	"math"
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

func TestCleanestFastestTakesTheFastestCleanLiveMember(t *testing.T) {
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

	if got := cleanestFastest(group, "", ""); got != "fast" {
		t.Errorf("picked %q, want the fastest clean one", got)
	}
}

func TestCleanestFastestKeepsTheOneInUseWhileItAnswers(t *testing.T) {
	test := useTestPurity(t)
	test.know("a", "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	test.know("b", "2.2.2.2", time.Minute, ipVerdict{Type: "residential"})
	group := members(stubMember{name: "a", delay: 900}, stubMember{name: "b", delay: 10})

	if got := cleanestFastest(group, "", "a"); got != "a" {
		t.Errorf("picked %q, want the one in use kept however slow", got)
	}
	unchecked := members(stubMember{name: "new", delay: 900}, stubMember{name: "b", delay: 10})
	if got := cleanestFastest(unchecked, "", "new"); got != "new" {
		t.Errorf("picked %q, want no move while the one in use is being checked", got)
	}
}

func TestCleanestFastestLeavesADeadOrUncleanMember(t *testing.T) {
	test := useTestPurity(t)
	test.know("a", "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	test.know("same", "1.1.1.1", time.Minute, ipVerdict{Type: "residential"})
	test.know("other", "2.2.2.2", time.Minute, ipVerdict{Type: "residential"})
	test.know("dc", "3.3.3.3", time.Minute, ipVerdict{Type: "hosting"})
	dead := members(
		stubMember{name: "a", delay: 900, dead: true},
		stubMember{name: "same", delay: 300},
		stubMember{name: "other", delay: 10},
	)
	if got := cleanestFastest(dead, "", "a"); got != "same" {
		t.Errorf("picked %q, want the member on the same address first", got)
	}
	alone := members(stubMember{name: "a", dead: true}, stubMember{name: "other", delay: 10})
	if got := cleanestFastest(alone, "", "a"); got != "other" {
		t.Errorf("picked %q, want the fastest clean member on another address", got)
	}
	unclean := members(stubMember{name: "dc", delay: 5}, stubMember{name: "other", delay: 400})
	if got := cleanestFastest(unclean, "", "dc"); got != "other" {
		t.Errorf("picked %q, want the unclean member left", got)
	}
	if got := cleanestFastest(members(stubMember{name: "a", dead: true}), "", "a"); got != "" {
		t.Errorf("picked %q, want the choice left to url-test", got)
	}
}

func TestCleanestFastestLeavesTheChoiceWhileNoneIsKnownClean(t *testing.T) {
	test := useTestPurity(t)

	got := cleanestFastest(members(stubMember{name: "x", delay: math.MaxUint16}), "", "")

	if got != "" {
		t.Errorf("picked %q, want none", got)
	}
	test.settle(t)
	if test.askedFor("x") != 1 {
		t.Error("an unchecked member was not checked")
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
