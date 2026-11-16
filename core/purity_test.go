package core

import (
	"context"
	"errors"
	"reflect"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
)

type purityChange struct {
	node  string
	level purityLevel
}

type testPurity struct {
	book    *purityBook
	mu      sync.Mutex
	exits   map[string]string
	ips     map[string]ipVerdict
	asked   map[string]int
	changes []purityChange
}

// useTestPurity swaps in an empty book whose lookups answer from the maps.
func useTestPurity(t *testing.T) *testPurity {
	t.Helper()
	home := t.TempDir()
	previousHome := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	test := &testPurity{
		book:  &purityBook{},
		exits: map[string]string{},
		ips:   map[string]ipVerdict{},
		asked: map[string]int{},
	}
	previousBook, previousSave := purity, puritySave
	previousExit, previousVerdict, previousChanged := lookupNodeExit, lookupIpVerdict, purityChanged
	purity, puritySave = test.book, 10*time.Millisecond
	lookupNodeExit = func(node string) nodeExit {
		test.mu.Lock()
		defer test.mu.Unlock()
		test.asked[node]++
		return nodeExit{ip: test.exits[node], at: time.Now()}
	}
	lookupIpVerdict = func(_, ip string) (ipVerdict, error) {
		test.mu.Lock()
		defer test.mu.Unlock()
		verdict, ok := test.ips[ip]
		if !ok {
			return ipVerdict{}, errQualityFailed
		}
		return verdict, nil
	}
	purityChanged = func(node string, level purityLevel) {
		test.mu.Lock()
		defer test.mu.Unlock()
		test.changes = append(test.changes, purityChange{node, level})
	}
	t.Cleanup(func() {
		test.settle(t)
		flushPurity(t, test.book)
		purity, puritySave = previousBook, previousSave
		lookupNodeExit, lookupIpVerdict, purityChanged = previousExit, previousVerdict, previousChanged
		constant.SetHomeDir(previousHome)
	})
	return test
}

func (p *testPurity) settle(t *testing.T) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for {
		p.book.mu.Lock()
		checking := len(p.book.checking)
		p.book.mu.Unlock()
		if checking == 0 {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("a check never finished")
		}
		time.Sleep(time.Millisecond)
	}
}

func (p *testPurity) askedFor(node string) int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.asked[node]
}

// waitChanges waits out the call that follows a settled check.
func (p *testPurity) waitChanges(t *testing.T, want []purityChange) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for {
		p.mu.Lock()
		got := append([]purityChange(nil), p.changes...)
		p.mu.Unlock()
		if reflect.DeepEqual(got, want) {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("changes = %v, want %v", got, want)
		}
		time.Sleep(time.Millisecond)
	}
}

func (p *testPurity) know(node, ip string, age time.Duration, verdict ipVerdict) {
	p.book.mu.Lock()
	defer p.book.mu.Unlock()
	p.book.load()
	if verdict.At == 0 {
		verdict.At = time.Now().UnixMilli()
	}
	p.book.record.Nodes[node] = nodeAddress{Ip: ip, At: time.Now().Add(-age).UnixMilli()}
	p.book.record.Ips[ip] = verdict
}

func flushPurity(t *testing.T, book *purityBook) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for {
		book.mu.Lock()
		saving := book.saving
		book.mu.Unlock()
		if !saving {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the record was never saved")
		}
		time.Sleep(time.Millisecond)
	}
	book.writing.Lock()
	defer book.writing.Unlock()
}

func TestIpVerdictLevelFollowsTheHostsGrades(t *testing.T) {
	cases := map[purityLevel][]ipVerdict{
		purityGood:    {{Type: "residential"}, {Type: "mobile"}, {Type: "business"}},
		purityNormal:  {{Type: "hosting"}},
		purityRisky:   {{Type: "residential", Tor: true}, {Type: "hosting", Abuser: true}},
		purityUnknown: {{}},
	}
	for want, verdicts := range cases {
		for _, verdict := range verdicts {
			if got := verdict.level(); got != want {
				t.Errorf("%+v.level() = %v, want %v", verdict, got, want)
			}
		}
	}
}

func TestQualitySourcesReadTheirAnswers(t *testing.T) {
	cases := []struct {
		source   qualitySource
		body     map[string]any
		want     ipVerdict
		inferred bool
		err      error
	}{
		{ipApiComSource, map[string]any{"status": "success", "hosting": true}, ipVerdict{Type: "hosting"}, false, nil},
		{ipApiComSource, map[string]any{"status": "success"}, ipVerdict{Type: "residential"}, true, nil},
		{ipApiComSource, map[string]any{"status": "fail"}, ipVerdict{}, false, errQualityFailed},
		{ipQuerySource, map[string]any{"risk": map[string]any{"is_mobile": true}}, ipVerdict{Type: "mobile"}, false, nil},
		{ipQuerySource, map[string]any{"risk": map[string]any{"is_tor": true}}, ipVerdict{Type: "residential", Tor: true}, true, nil},
		{ipLocateSource, map[string]any{"company": map[string]any{"type": "isp"}, "privacy": map[string]any{"is_abuser": true}}, ipVerdict{Type: "residential", Abuser: true}, false, nil},
		{ipLocateSource, map[string]any{"asn": map[string]any{"type": "education"}}, ipVerdict{Type: "business"}, false, nil},
		{ipLocateSource, map[string]any{}, ipVerdict{}, false, errQualityNoType},
		{ipApiIsSource, map[string]any{"is_datacenter": true, "company": map[string]any{"type": "isp"}}, ipVerdict{Type: "hosting"}, false, nil},
		{ipApiIsSource, map[string]any{"asn": map[string]any{"type": "hosting"}}, ipVerdict{Type: "hosting"}, false, nil},
		{proxyCheckSource, map[string]any{"status": "ok", "1.2.3.4": map[string]any{"network": map[string]any{"type": "Wireless"}}}, ipVerdict{Type: "mobile"}, false, nil},
		{proxyCheckSource, map[string]any{"status": "warning", "1.2.3.4": map[string]any{"network": map[string]any{"type": "Residential"}, "detections": map[string]any{"tor": true}}}, ipVerdict{Type: "residential", Tor: true}, false, nil},
		{proxyCheckSource, map[string]any{"status": "denied"}, ipVerdict{}, false, errQualityRateLimited},
	}
	for _, c := range cases {
		got, inferred, err := c.source.parse("1.2.3.4", c.body)
		if !errors.Is(err, c.err) || err == nil && (got != c.want || inferred != c.inferred) {
			t.Errorf("%s(%v) = %+v, %v, %v; want %+v, %v, %v", c.source.name, c.body, got, inferred, err, c.want, c.inferred, c.err)
		}
	}
}

func useQualityAnswers(t *testing.T, answers map[string]func(ctx context.Context) qualityAnswer) *atomic.Int32 {
	t.Helper()
	asked := &atomic.Int32{}
	previousAsk, previousHedge := askQuality, qualityHedge
	askQuality = func(ctx context.Context, source qualitySource, _, _ string) qualityAnswer {
		asked.Add(1)
		answer, ok := answers[source.name]
		if !ok {
			return qualityAnswer{err: errQualityFailed}
		}
		return answer(ctx)
	}
	qualityHedge = 20 * time.Millisecond
	t.Cleanup(func() { askQuality, qualityHedge = previousAsk, previousHedge })
	return asked
}

func stated(kind string) func(context.Context) qualityAnswer {
	return func(context.Context) qualityAnswer { return qualityAnswer{verdict: ipVerdict{Type: kind}} }
}

func TestQueryIpVerdictTakesTheFirstStatedType(t *testing.T) {
	useQualityAnswers(t, map[string]func(context.Context) qualityAnswer{
		"ipApiCom": func(context.Context) qualityAnswer {
			return qualityAnswer{verdict: ipVerdict{Type: "residential"}, inferred: true}
		},
		"ipQuery": stated("hosting"),
	})

	got, err := queryIpVerdict("node", "1.2.3.4")

	if err != nil || got.Type != "hosting" || got.Source != "ipQuery" {
		t.Errorf("verdict = %+v, %v; want hosting from ipQuery", got, err)
	}
}

func TestQueryIpVerdictFallsBackToAnInferredType(t *testing.T) {
	asked := useQualityAnswers(t, map[string]func(context.Context) qualityAnswer{
		"ipApiCom": func(context.Context) qualityAnswer {
			return qualityAnswer{verdict: ipVerdict{Type: "residential"}, inferred: true}
		},
	})

	got, err := queryIpVerdict("node", "1.2.3.4")

	if err != nil || got.Type != "residential" || got.Source != "ipApiCom" {
		t.Errorf("verdict = %+v, %v; want the inferred residential", got, err)
	}
	if n := asked.Load(); n != 5 {
		t.Errorf("asked %d sources, want every one before settling for a guess", n)
	}
}

func TestQueryIpVerdictFailsWhenNoSourceAnswers(t *testing.T) {
	useQualityAnswers(t, nil)

	if got, err := queryIpVerdict("node", "1.2.3.4"); err == nil {
		t.Errorf("verdict = %+v, want an error", got)
	}
}

func TestQueryIpVerdictHedgesPastASlowWave(t *testing.T) {
	slow := func(ctx context.Context) qualityAnswer {
		<-ctx.Done()
		return qualityAnswer{err: ctx.Err()}
	}
	useQualityAnswers(t, map[string]func(context.Context) qualityAnswer{
		"ipApiCom": slow,
		"ipQuery":  slow,
		"ipLocate": stated("business"),
	})

	start := time.Now()
	got, err := queryIpVerdict("node", "1.2.3.4")

	if err != nil || got.Type != "business" {
		t.Errorf("verdict = %+v, %v; want business from the second wave", got, err)
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Errorf("took %v, want the next wave started after the hedge", elapsed)
	}
}

func TestPurityBookChecksAnUnknownNodeOnce(t *testing.T) {
	test := useTestPurity(t)
	test.exits["jp"] = "1.1.1.1"
	test.ips["1.1.1.1"] = ipVerdict{Type: "residential"}

	if purity.allows("jp") || purity.allows("jp") {
		t.Fatal("an unchecked node let traffic through")
	}
	test.settle(t)

	if !purity.cleared("jp") || !purity.allows("jp") {
		t.Error("a clean node was not cleared once checked")
	}
	if n := test.askedFor("jp"); n != 1 {
		t.Errorf("looked up the exit %d times, want once", n)
	}
	test.waitChanges(t, []purityChange{{"jp", purityGood}})
}

func TestPurityBookTrustsAStaleCleanVerdictWhileItChecksAgain(t *testing.T) {
	test := useTestPurity(t)
	test.exits["stale"] = "4.4.4.4"
	test.ips["4.4.4.4"] = ipVerdict{Type: "hosting"}
	test.know("fresh", "1.1.1.1", time.Minute, ipVerdict{Type: "mobile"})
	test.know("stale", "2.2.2.2", purityFresh+time.Minute, ipVerdict{Type: "residential"})
	test.know("old", "3.3.3.3", purityTrusted+time.Minute, ipVerdict{Type: "residential"})

	if !purity.cleared("fresh") {
		t.Error("a node checked a minute ago was not cleared")
	}
	if purity.cleared("stale") || !purity.allows("stale") {
		t.Error("a stale clean verdict should let traffic through but not count as cleared")
	}
	if purity.allows("old") {
		t.Error("a verdict past the trusted window let traffic through")
	}
	test.settle(t)

	if purity.allows("stale") {
		t.Error("the node moved to a hosting address yet still lets traffic through")
	}
	if test.askedFor("fresh") != 0 {
		t.Error("a fresh node was checked again")
	}
}

func TestPurityBookRetriesAFailedCheckOnlyAfterAPause(t *testing.T) {
	test := useTestPurity(t)

	purity.levelOf("down")
	test.settle(t)
	purity.levelOf("down")
	test.settle(t)

	if n := test.askedFor("down"); n != 1 {
		t.Errorf("looked up %d times, want the failure to hold off a retry", n)
	}
}

func TestPurityBookObserveForgetsANodeThatMoved(t *testing.T) {
	test := useTestPurity(t)
	test.ips["9.9.9.9"] = ipVerdict{Type: "hosting"}
	test.know("jp", "1.1.1.1", purityFresh+time.Minute, ipVerdict{Type: "residential"})

	purity.observe("jp", "1.1.1.1")
	if !purity.cleared("jp") {
		t.Fatal("seeing the same address did not confirm the node")
	}
	purity.observe("jp", "9.9.9.9")
	if purity.allows("jp") {
		t.Error("a node that moved kept its old verdict")
	}
	test.settle(t)

	if level := purity.levelOf("jp"); level != purityNormal {
		t.Errorf("level = %v, want the new address's verdict", level)
	}
	test.waitChanges(t, []purityChange{{"jp", purityUnknown}, {"jp", purityNormal}})
	if test.askedFor("jp") != 0 {
		t.Error("the exit was looked up again though the record had found it")
	}
}

func TestPurityBookKeepsItsVerdictsAcrossARestart(t *testing.T) {
	test := useTestPurity(t)
	test.exits["jp"] = "1.1.1.1"
	test.ips["1.1.1.1"] = ipVerdict{Type: "residential"}
	purity.levelOf("jp")
	test.settle(t)
	flushPurity(t, test.book)

	restarted := &purityBook{}

	if !restarted.cleared("jp") {
		t.Error("a node checked before the restart was not cleared after it")
	}
}
