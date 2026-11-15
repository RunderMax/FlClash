package core

import (
	"regexp"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"
)

const appRoutesKey = "x-sloth-app-routes"

var appPackagePattern = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$`)

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
	known := namesOf(resolveAlias(mappingValue(root, "proxies")))
	for name := range namesOf(resolveAlias(mappingValue(root, "proxy-groups"))) {
		known[name] = true
	}
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

// mihomo trims each rule field, so a padded name would not resolve.
func routable(target string, known map[string]bool) bool {
	if target == "" || strings.Contains(target, ",") || strings.TrimSpace(target) != target {
		return false
	}
	return known[target] || builtInTargets[target]
}
