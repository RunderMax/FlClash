package core

import (
	"sync/atomic"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
	"go.yaml.in/yaml/v3"
)

// Unlike the other requests this stays in the written config, which the
// Android service loads again on its own.
const guardKey = "x-sloth-guard"

// Tells the host a stopped connection from a REJECT the user chose.
const guardOutbound = "Sloth Guard"

type guardRequest struct {
	All  bool     `yaml:"all"`
	Apps []string `yaml:"apps"`
}

type guardState struct {
	all  bool
	apps map[string]bool
}

var (
	loadedGuard  guardRequest
	currentGuard atomic.Pointer[guardState]
)

func init() {
	purityChanged = reactToPurity
}

func readGuardRequest(root *yaml.Node) {
	loadedGuard = guardRequest{}
	if request := resolveAlias(mappingValue(root, guardKey)); request != nil {
		_ = request.Decode(&loadedGuard)
	}
}

func newGuardState(request guardRequest) *guardState {
	apps := map[string]bool{}
	for _, app := range request.Apps {
		if appPackagePattern.MatchString(app) {
			apps[app] = true
		}
	}
	if !request.All && len(apps) == 0 {
		return nil
	}
	return &guardState{all: request.All, apps: apps}
}

func armGuard(cfg *config.Config) {
	cfg.Proxies[guardOutbound] = adapter.NewProxy(outbound.NewRejectWithOption(outbound.RejectOption{Name: guardOutbound}))
	cfg.Rules = guardedRules(cfg.Rules)
	for name, rules := range cfg.SubRules {
		cfg.SubRules[name] = guardedRules(rules)
	}
}

func guardedRules(rules []constant.Rule) []constant.Rule {
	guarded := make([]constant.Rule, len(rules))
	for i, rule := range rules {
		if wrapper, ok := rule.(constant.RuleWrapper); ok {
			guarded[i] = &guardedRuleWrapper{wrapper}
		} else {
			guarded[i] = &guardedRule{rule}
		}
	}
	return guarded
}

type guardedRule struct{ constant.Rule }

func (r *guardedRule) Match(metadata *constant.Metadata, helper constant.RuleMatchHelper) (bool, string) {
	matched, name := r.Rule.Match(metadata, helper)
	if matched {
		name = guardRoute(metadata, helper, name)
	}
	return matched, name
}

// The controller's rule API asks for the wrapper mihomo puts on every rule.
type guardedRuleWrapper struct{ constant.RuleWrapper }

func (r *guardedRuleWrapper) Match(metadata *constant.Metadata, helper constant.RuleMatchHelper) (bool, string) {
	matched, name := r.RuleWrapper.Match(metadata, helper)
	if matched {
		name = guardRoute(metadata, helper, name)
	}
	return matched, name
}

// guardRoute runs under the tunnel's config lock, so it must not take it again.
func guardRoute(metadata *constant.Metadata, helper constant.RuleMatchHelper, name string) string {
	state := currentGuard.Load()
	if state == nil {
		return name
	}
	proxy := tunnel.Proxies()[name]
	if proxy == nil {
		return name
	}
	node := finalNode(proxy, metadata)
	if !isProxied(node) || purity.cleared(node.Name()) {
		return name
	}
	if !state.all {
		if metadata.Process == "" && helper.FindProcess != nil {
			helper.FindProcess()
		}
		if !state.apps[metadata.Process] {
			return name
		}
	}
	if purity.allows(node.Name()) {
		return name
	}
	return guardOutbound
}

func finalNode(proxy constant.Proxy, metadata *constant.Metadata) constant.Proxy {
	for range 32 {
		next := proxy.Unwrap(metadata, false)
		if next == nil {
			break
		}
		proxy = next
	}
	return proxy
}

func isProxied(proxy constant.Proxy) bool {
	switch proxy.Type() {
	case constant.Direct, constant.Reject, constant.RejectDrop, constant.Compatible,
		constant.Pass, constant.PassRule, constant.Rematch, constant.Dns:
		return false
	}
	return true
}

// guardJoined stops what never met the rules, as in Global mode, after it dialed.
func guardJoined(tracker statistic.Tracker) bool {
	state := currentGuard.Load()
	if state == nil || !blockedByGuard(state, tracker.Info()) {
		return false
	}
	_ = tracker.Close()
	return true
}

func blockedByGuard(state *guardState, info *statistic.TrackerInfo) bool {
	if len(info.Chain) == 0 {
		return false
	}
	node := info.Chain[0]
	if node == guardOutbound || purity.cleared(node) {
		return false
	}
	proxy := lookupProxy(node)
	if proxy == nil || !isProxied(proxy) {
		return false
	}
	if !state.all && !state.apps[appOf(info.Metadata)] {
		return false
	}
	return !purity.allows(node)
}

// An empty [node] sweeps every node.
func sweepGuarded(node string) {
	state := currentGuard.Load()
	if state == nil {
		return
	}
	statistic.DefaultManager.Range(func(tracker statistic.Tracker) bool {
		info := tracker.Info()
		through := node == "" || len(info.Chain) > 0 && info.Chain[0] == node
		if through && blockedByGuard(state, info) {
			_ = tracker.Close()
		}
		return true
	})
}

func reactToPurity(node string, level purityLevel) {
	if level != purityGood {
		go sweepGuarded(node)
	}
	steering.nudge()
}

func warmGuard(state *guardState, rules []constant.Rule) {
	if state == nil {
		return
	}
	proxies := tunnel.Proxies()
	warm := func(name string) {
		if proxy := proxies[name]; proxy != nil {
			if node := finalNode(proxy, &constant.Metadata{}); isProxied(node) {
				purity.levelOf(node.Name())
			}
		}
	}
	if state.all {
		for i := len(rules) - 1; i >= 0; i-- {
			if rules[i].RuleType() == constant.MATCH {
				warm(rules[i].Adapter())
				break
			}
		}
	}
	for app, target := range appliedAppRoutes {
		if state.all || state.apps[app] {
			warm(target)
		}
	}
	go sweepGuarded("")
}
