package core

import (
	"bufio"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
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

type steerer struct {
	mu      sync.Mutex
	groups  []string
	pinned  map[string]string
	applied map[string]bool
	down    map[string]time.Time
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
	if s.down == nil {
		s.down = map[string]time.Time{}
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
		downFor := s.downForLocked(name, pinned, members, url, time.Now())
		s.mu.Unlock()
		target := nextPick(members, url, pinned, downFor)
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

// nextPick never moves the exit to another country: with no clean live member
// on the same address or in the same country it stays on the one in use.
func nextPick(members []constant.Proxy, url, current string, downFor time.Duration) string {
	var inUse constant.Proxy
	for _, member := range members {
		if member.Name() == current {
			inUse = member
		}
	}
	if inUse == nil {
		return fastestClean(members, url)
	}
	level := purity.levelOf(current)
	clean := level == purityGood || level == purityUnknown
	if clean && (inUse.AliveForTestUrl(url) || downFor < leaveDeadAfter) {
		return current
	}
	exit := purity.exitOf(current)
	country := countryOf(exit)
	rates := failureRates()
	best, bestRank := current, [3]int{}
	for _, member := range members {
		name := member.Name()
		if name == current || purity.levelOf(name) != purityGood || !member.AliveForTestUrl(url) {
			continue
		}
		other := purity.exitOf(name)
		sameExit := exit != "" && other == exit
		if !sameExit && (country == "" || countryOf(other) != country) {
			continue
		}
		rank := [3]int{1, int(rates[name] * 10), int(member.LastDelayForTestUrl(url))}
		if sameExit {
			rank[0] = 0
		}
		if best == current || slices.Compare(rank[:], bestRank[:]) < 0 {
			best, bestRank = name, rank
		}
	}
	return best
}

func fastestClean(members []constant.Proxy, url string) string {
	best, bestDelay := "", 0
	for _, member := range members {
		if purity.levelOf(member.Name()) != purityGood || !member.AliveForTestUrl(url) {
			continue
		}
		if delay := int(member.LastDelayForTestUrl(url)); best == "" || delay < bestDelay {
			best, bestDelay = member.Name(), delay
		}
	}
	return best
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

var failureRates = func() map[string]float64 {
	file, err := os.Open(filepath.Join(constant.Path.HomeDir(), pickHistoryFile))
	if err != nil {
		return nil
	}
	defer file.Close()
	total, failed := map[string]int{}, map[string]int{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		var sample pickSample
		if json.Unmarshal(scanner.Bytes(), &sample) != nil {
			continue
		}
		total[sample.Name]++
		if sample.Delay == 0 {
			failed[sample.Name]++
		}
	}
	rates := make(map[string]float64, len(total))
	for name, count := range total {
		rates[name] = float64(failed[name]) / float64(count)
	}
	return rates
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
