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
	gen     uint64
	started bool
	poke    chan struct{}
}

var steering = &steerer{poke: make(chan struct{}, 1)}

func isPickGroup(name string) bool {
	return name == slothPickGroup || strings.HasPrefix(name, appPickGroupPrefix)
}

// reset forgets every pin, since the applied config may have pinned a group
// from the host's saved selection since.
func (s *steerer) reset(proxies map[string]constant.Proxy) {
	names := autoPickGroups(proxies)
	s.mu.Lock()
	s.groups, s.pinned = names, map[string]string{}
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
		pinned, known := s.pinned[name]
		s.mu.Unlock()
		target := cleanestFastest(group.Proxies(), urlTestURL(group), pinned)
		if known && target == pinned {
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
		s.mu.Unlock()
		changed = true
	}
	if changed {
		refreshRoute()
	}
}

// cleanestFastest names no member while none is known clean, which leaves the
// choice to url-test; the one in use stays while it is within tolerance.
func cleanestFastest(members []constant.Proxy, url, current string) string {
	best, bestDelay := "", 0
	currentDelay, currentClean := 0, false
	for _, member := range members {
		if purity.levelOf(member.Name()) != purityGood || !member.AliveForTestUrl(url) {
			continue
		}
		delay := int(member.LastDelayForTestUrl(url))
		if member.Name() == current {
			currentDelay, currentClean = delay, true
		}
		if best == "" || delay < bestDelay {
			best, bestDelay = member.Name(), delay
		}
	}
	if currentClean && currentDelay <= bestDelay+defaultFastestTolerance {
		return current
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
