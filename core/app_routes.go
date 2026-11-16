package core

import (
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel/statistic"
	"go.yaml.in/yaml/v3"
)

const appRoutesKey = "x-sloth-app-routes"

// Android package names and Windows executable names, both of which a
// PROCESS-NAME rule matches; a comma would end the rule's payload early.
var appPackagePattern = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_ \-]*(\.[A-Za-z0-9_\-]+)+$`)

var builtInTargets = map[string]bool{
	"DIRECT":      true,
	"REJECT":      true,
	"REJECT-DROP": true,
	"PASS":        true,
	"COMPATIBLE":  true,
	"GLOBAL":      true,
}

// A route to a name the profile lost is dropped: mihomo refuses the whole
// config over one rule it cannot resolve.
func applyAppRoutes(root *yaml.Node) {
	request := resolveAlias(deleteMappingValue(root, appRoutesKey))
	if request == nil || request.Kind != yaml.MappingNode {
		return
	}
	routes := resolveAlias(mappingValue(request, "routes"))
	if routes == nil || routes.Kind != yaml.MappingNode {
		return
	}
	nodes := namesOf(resolveAlias(mappingValue(root, "proxies")))
	known := namesOf(resolveAlias(mappingValue(root, "proxy-groups")))
	for name := range nodes {
		known[name] = true
	}
	addAppPickGroups(root, resolveAlias(mappingValue(request, "picks")), routes, nodes, known)
	var added []*yaml.Node
	for i := 0; i+1 < len(routes.Content); i += 2 {
		app, target := scalarOf(routes.Content[i]), scalarOf(routes.Content[i+1])
		if !appPackagePattern.MatchString(app) || !routable(target, known) {
			continue
		}
		added = append(added, &yaml.Node{
			Kind:  yaml.ScalarNode,
			Tag:   "!!str",
			Value: "PROCESS-NAME," + app + "," + target,
		})
	}
	if len(added) == 0 {
		return
	}
	var existing []*yaml.Node
	if rules := resolveAlias(mappingValue(root, "rules")); rules != nil && !isNull(rules) {
		if rules.Kind != yaml.SequenceNode {
			return
		}
		existing = rules.Content
	}
	at, _ := strconv.Atoi(scalarOf(mappingValue(request, "at")))
	at = min(max(at, 0), len(existing))
	content := make([]*yaml.Node, 0, len(existing)+len(added))
	content = append(content, existing[:at]...)
	content = append(content, added...)
	content = append(content, existing[at:]...)
	setMappingValue(root, "rules", &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq", Content: content})
}

type appPickSpec struct {
	Proxies []string `yaml:"proxies"`
	Auto    bool     `yaml:"auto"`
}

// An app routed to its own picks gets a hidden group of the ones the profile
// still has.
func addAppPickGroups(root, picks, routes *yaml.Node, nodes, known map[string]bool) {
	if picks == nil || picks.Kind != yaml.MappingNode {
		return
	}
	groups := resolveAlias(mappingValue(root, "proxy-groups"))
	var content []*yaml.Node
	if groups != nil && !isNull(groups) {
		if groups.Kind != yaml.SequenceNode {
			return
		}
		content = append(content, groups.Content...)
	}
	targets := map[string]string{}
	for i := 0; i+1 < len(routes.Content); i += 2 {
		targets[scalarOf(routes.Content[i])] = scalarOf(routes.Content[i+1])
	}
	added := 0
	for i := 0; i+1 < len(picks.Content); i += 2 {
		app := scalarOf(picks.Content[i])
		name := appPickGroupPrefix + app
		var spec appPickSpec
		if !appPackagePattern.MatchString(app) || targets[app] != name || known[name] ||
			resolveAlias(picks.Content[i+1]).Decode(&spec) != nil {
			continue
		}
		var members []string
		for _, member := range spec.Proxies {
			if nodes[member] && !slices.Contains(members, member) {
				members = append(members, member)
			}
		}
		group, err := appPickGroupNode(name, members, spec.Auto)
		if len(members) == 0 || err != nil {
			continue
		}
		content = append(content, group)
		known[name] = true
		added++
	}
	if added > 0 {
		setMappingValue(root, "proxy-groups", &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq", Content: content})
	}
}

func appPickGroupNode(name string, members []string, auto bool) (*yaml.Node, error) {
	group := map[string]any{"name": name, "type": "select", "proxies": members, "hidden": true}
	if auto {
		group["type"] = "url-test"
		group["url"] = defaultFastestURL
		group["interval"] = defaultFastestInterval
		group["tolerance"] = defaultFastestTolerance
	}
	var node yaml.Node
	err := node.Encode(group)
	return &node, err
}

// mihomo trims each rule field, so a padded name would not resolve.
func routable(target string, known map[string]bool) bool {
	if target == "" || strings.Contains(target, ",") || strings.TrimSpace(target) != target {
		return false
	}
	return known[target] || builtInTargets[target]
}

var appliedAppRoutes map[string]string

// A connection keeps the way it was opened on, and apps hold theirs open for
// minutes, so an app whose route changed has its connections closed.
func reapplyAppRoutes(rules []constant.Rule) {
	routes := appRoutesOf(rules)
	changed := changedApps(appliedAppRoutes, routes)
	appliedAppRoutes = routes
	if len(changed) > 0 {
		go closeAppConnections(changed)
	}
}

func appRoutesOf(rules []constant.Rule) map[string]string {
	routes := map[string]string{}
	for _, rule := range rules {
		if rule.RuleType() != constant.ProcessName {
			continue
		}
		if _, seen := routes[rule.Payload()]; !seen {
			routes[rule.Payload()] = rule.Adapter()
		}
	}
	return routes
}

func changedApps(before, after map[string]string) map[string]bool {
	changed := map[string]bool{}
	for app, target := range before {
		if after[app] != target {
			changed[app] = true
		}
	}
	for app, target := range after {
		if before[app] != target {
			changed[app] = true
		}
	}
	return changed
}

func closeAppConnections(apps map[string]bool) {
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		if apps[appOf(c.Info().Metadata)] {
			_ = c.Close()
		}
		return true
	})
}

// A connection opened while no rule asked for its app was never looked up.
func appOf(metadata *constant.Metadata) string {
	if metadata == nil {
		return ""
	}
	if metadata.Process != "" {
		return metadata.Process
	}
	lookup := *metadata
	name, _ := process.FindPackageName(&lookup)
	return name
}
