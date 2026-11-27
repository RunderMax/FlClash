package core

import (
	"encoding/json"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/constant"
)

// The host names its picks groups so; a url-test one among them is steered to
// the fastest clean member, which url-test alone would not look for.
const (
	slothPickGroup     = "Sloth Pick"
	appPickGroupPrefix = "Sloth Pick · "
)

var steerEvery = time.Minute

type steerer struct {
	mu      sync.Mutex
	groups  []string
	pinned  map[string]string
	applied map[string]bool
	gen     uint64
	started bool
	poke    chan struct{}
}

var steering = &steerer{poke: make(chan struct{}, 1)}

func isPickGroup(name string) bool {
	return name == slothPickGroup || strings.HasPrefix(name, appPickGroupPrefix)
}

func (s *steerer) reset(proxies map[string]constant.Proxy) {
	names := autoPickGroups(proxies)
	s.mu.Lock()
	pinned := map[string]string{}
	for _, name := range names {
		if pin, ok := s.pinned[name]; ok {
			pinned[name] = pin
		}
	}
	s.groups, s.pinned, s.applied = names, pinned, map[string]bool{}
	s.gen++
	start := len(names) > 0 && !s.started
	s.started = s.started || start
	s.mu.Unlock()
	if start {
		go s.run()
	}
	s.nudge()
}

func autoPickGroups(proxies map[string]constant.Proxy) []string {
	var names []string
	for name, proxy := range proxies {
		if isPickGroup(name) && proxy.Type() == constant.URLTest {
			names = append(names, name)
		}
	}
	slices.Sort(names)
	return names
}

func (s *steerer) nudge() {
	select {
	case s.poke <- struct{}{}:
	default:
	}
}

func (s *steerer) run() {
	ticker := time.NewTicker(steerEvery)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
		case <-s.poke:
		}
		s.steer()
	}
}

func (s *steerer) steer() {
	s.mu.Lock()
	names, gen := slices.Clone(s.groups), s.gen
	s.mu.Unlock()
	changed := false
	for _, name := range names {
		group, ok := adapterAs[*outboundgroup.URLTest](lookupProxy(name))
		if !ok {
			continue
		}
		s.mu.Lock()
		pinned, applied := s.pinned[name], s.applied[name]
		s.mu.Unlock()
		target := cleanestFastest(group.Proxies(), urlTestURL(group), pinned)
		if applied && target == pinned {
			continue
		}
		s.mu.Lock()
		if s.gen != gen {
			s.mu.Unlock()
			return
		}
		selectMu.Lock()
		group.ForceSet(target)
		selectMu.Unlock()
		s.pinned[name] = target
		s.applied[name] = true
		s.mu.Unlock()
		changed = true
	}
	if changed {
		refreshRoute()
	}
}

// cleanestFastest leaves the member in use only once it is dead or unclean; an empty name leaves url-test to choose.
func cleanestFastest(members []constant.Proxy, url, current string) string {
	exit := ""
	if current != "" {
		exit = purity.exitOf(current)
	}
	best, bestDelay := "", 0
	same, sameDelay := "", 0
	for _, member := range members {
		name := member.Name()
		level, alive := purity.levelOf(name), member.AliveForTestUrl(url)
		if name == current && alive && (level == purityGood || level == purityUnknown) {
			return current
		}
		if level != purityGood || !alive {
			continue
		}
		delay := int(member.LastDelayForTestUrl(url))
		if best == "" || delay < bestDelay {
			best, bestDelay = name, delay
		}
		if exit != "" && purity.exitOf(name) == exit && (same == "" || delay < sameDelay) {
			same, sameDelay = name, delay
		}
	}
	if same != "" {
		return same
	}
	return best
}

func urlTestURL(group *outboundgroup.URLTest) string {
	var fields struct {
		TestUrl string `json:"testUrl"`
	}
	if buf, err := group.MarshalJSON(); err == nil && json.Unmarshal(buf, &fields) == nil && fields.TestUrl != "" {
		return fields.TestUrl
	}
	return defaultFastestURL
}
