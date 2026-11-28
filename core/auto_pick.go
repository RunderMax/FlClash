package core

import (
	"encoding/json"
	"net"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/constant"
)

// The host names its picks groups so; a url-test one among them is steered to
// the fastest clean member, which url-test alone would not look for.
const (
	slothPickGroup     = "Sloth Pick"
	appPickGroupPrefix = "Sloth Pick · "
)

var steerEvery = time.Minute

// One failed check is often the network, not the node.
const leaveDeadAfter = 2 * time.Minute

// Each return cuts what is open, so a line only just back is not trusted yet.
const returnAfter = 10 * time.Minute

type steerer struct {
	mu      sync.Mutex
	groups  []string
	pinned  map[string]string
	applied map[string]bool
	down    map[string]time.Time
	up      map[string]time.Time
	lead    map[string]string
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
	pinned, lead := map[string]string{}, map[string]string{}
	for _, name := range names {
		lead[name] = leadOf(proxies[name])
		// A new main line is taken at once.
		if pin, ok := s.pinned[name]; ok && lead[name] == s.lead[name] {
			pinned[name] = pin
		}
	}
	s.groups, s.pinned, s.lead, s.applied = names, pinned, lead, map[string]bool{}
	if s.down == nil {
		s.down, s.up = map[string]time.Time{}, map[string]time.Time{}
	}
	s.gen++
	start := len(names) > 0 && !s.started
	s.started = s.started || start
	s.mu.Unlock()
	if start {
		go s.run()
	}
	s.nudge()
}

func leadOf(proxy constant.Proxy) string {
	group, ok := adapterAs[*outboundgroup.URLTest](proxy)
	if !ok || len(group.Proxies()) == 0 {
		return ""
	}
	return group.Proxies()[0].Name()
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
		members, url := group.Proxies(), urlTestURL(group)
		s.mu.Lock()
		pinned, applied := s.pinned[name], s.applied[name]
		now := time.Now()
		downFor := s.downForLocked(name, pinned, members, url, now)
		steady := s.steadyLocked(name, members, url, now)
		s.mu.Unlock()
		target := nextPick(members, url, pinned, downFor, steady)
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
		if target != pinned {
			delete(s.down, name)
		}
		s.pinned[name] = target
		s.applied[name] = true
		s.mu.Unlock()
		changed = true
	}
	if changed {
		refreshRoute()
	}
}

func (s *steerer) downForLocked(group, current string, members []constant.Proxy, url string, now time.Time) time.Duration {
	for _, member := range members {
		if member.Name() != current {
			continue
		}
		if member.AliveForTestUrl(url) {
			break
		}
		since, ok := s.down[group]
		if !ok {
			s.down[group] = now
			return 0
		}
		return now.Sub(since)
	}
	delete(s.down, group)
	return 0
}

func (s *steerer) steadyLocked(group string, members []constant.Proxy, url string, now time.Time) map[string]time.Duration {
	steady := make(map[string]time.Duration, len(members))
	for _, member := range members {
		key := group + "\x00" + member.Name()
		if !member.AliveForTestUrl(url) {
			delete(s.up, key)
			continue
		}
		since, ok := s.up[key]
		if !ok {
			since = now
			s.up[key] = now
		}
		steady[member.Name()] = now.Sub(since)
	}
	return steady
}

// The user's order ranks the members, the main line first; the exit never
// moves to another country.
func nextPick(members []constant.Proxy, url, current string, downFor time.Duration, steady map[string]time.Duration) string {
	at := slices.IndexFunc(members, func(member constant.Proxy) bool { return member.Name() == current })
	if at < 0 {
		return firstClean(members, url)
	}
	level := purity.levelOf(current)
	clean := level == purityGood || level == purityUnknown
	stays := clean && (members[at].AliveForTestUrl(url) || downFor < leaveDeadAfter)
	exit := purity.exitOf(current)
	country := countryOf(exit)
	inCountry := ""
	for i, member := range members {
		name := member.Name()
		if stays && i >= at {
			break
		}
		if i == at || purity.levelOf(name) != purityGood || !member.AliveForTestUrl(url) {
			continue
		}
		if stays && steady[name] < returnAfter {
			continue
		}
		other := purity.exitOf(name)
		if stays || (exit != "" && other == exit) {
			if stays && other != exit && (country == "" || countryOf(other) != country) {
				continue
			}
			return name
		}
		if inCountry == "" && country != "" && countryOf(other) == country {
			inCountry = name
		}
	}
	if inCountry != "" {
		return inCountry
	}
	return current
}

func firstClean(members []constant.Proxy, url string) string {
	for _, member := range members {
		if purity.levelOf(member.Name()) == purityGood && member.AliveForTestUrl(url) {
			return member.Name()
		}
	}
	return ""
}

// IPInstance ends the process when the database cannot be opened.
var countryOf = func(ip string) string {
	addr := net.ParseIP(ip)
	if addr == nil || !mmdb.Verify(constant.Path.MMDB()) {
		return ""
	}
	codes := mmdb.IPInstance().LookupCode(addr)
	if len(codes) == 0 {
		return ""
	}
	return strings.ToUpper(codes[0])
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
