package core

import (
	"fmt"
	"strings"
	"time"

	"go.yaml.in/yaml/v3"
)

// The host asks for its url-test group by this key, since the profile's
// groups and proxies stay in the Core and never reach it.
const fastestGroupKey = "x-sloth-fastest"

const (
	defaultFastestURL = "https://www.gstatic.com/generate_204"
	// A member that stopped answering is left only once a check says so, and
	// the group is checked only while traffic uses it.
	defaultFastestInterval  = 60
	defaultFastestTolerance = 50
)

type fastestGroupSpec struct {
	Name      string   `yaml:"name"`
	Type      string   `yaml:"type"`
	Proxies   []string `yaml:"proxies"`
	URL       string   `yaml:"url"`
	Interval  int      `yaml:"interval"`
	Tolerance int      `yaml:"tolerance"`
	// Minutes between two records of the members' delays; zero keeps none.
	Record int `yaml:"record"`
}

// The group the last applied config asked to have its members' delays kept,
// and how often.
var (
	recordedPicksGroup string
	recordedPicksEvery time.Duration
)

// applyFastestGroup turns the request into a group of the chosen proxies the
// profile still has, offered last in every select group so each keeps its own
// default first; rules send traffic to any of them, not only the first. A
// name the profile no longer has is dropped, since mihomo refuses a group
// that names a proxy it cannot find.
func applyFastestGroup(root *yaml.Node) error {
	request := deleteMappingValue(root, fastestGroupKey)
	if request == nil {
		return nil
	}
	var spec fastestGroupSpec
	if err := resolveAlias(request).Decode(&spec); err != nil {
		return fmt.Errorf("%s: %w", fastestGroupKey, err)
	}
	groups := resolveAlias(mappingValue(root, "proxy-groups"))
	if spec.Name == "" || groups == nil || groups.Kind != yaml.SequenceNode {
		return nil
	}
	known := namesOf(resolveAlias(mappingValue(root, "proxies")))
	for _, group := range groups.Content {
		if nameOf(group) == spec.Name {
			return nil
		}
	}
	proxies := make([]string, 0, len(spec.Proxies))
	for _, name := range spec.Proxies {
		if known[name] {
			proxies = append(proxies, name)
		}
	}
	if len(proxies) == 0 {
		return nil
	}
	added, err := fastestGroupNodes(spec, proxies)
	if err != nil {
		return err
	}
	if spec.Record > 0 {
		recordedPicksGroup = spec.Name
		recordedPicksEvery = time.Duration(spec.Record) * time.Minute
	}
	content := make([]*yaml.Node, 0, len(groups.Content)+len(added))
	content = append(append(content, groups.Content...), added...)
	setMappingValue(root, "proxy-groups", &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq", Content: content})
	for _, candidate := range groups.Content {
		candidate = resolveAlias(candidate)
		if candidate.Kind != yaml.MappingNode || scalarOf(mappingValue(candidate, "type")) != "select" ||
			isPickGroup(nameOf(candidate)) {
			continue
		}
		offerLast(candidate, spec.Name)
	}
	return nil
}

// A url-test group drops a member the moment one check of it fails, so an
// automatic group holds its members in a select group of its own, the line,
// which the steerer alone moves; the url-test group keeps only that line.
func fastestGroupNodes(spec fastestGroupSpec, proxies []string) ([]*yaml.Node, error) {
	if spec.Type == "select" {
		group, err := fastestGroupNode(spec, proxies)
		return []*yaml.Node{group}, err
	}
	line, err := lineNode(spec.Name, proxies)
	if err != nil {
		return nil, err
	}
	group, err := fastestGroupNode(spec, []string{lineOf(spec.Name)})
	return []*yaml.Node{line, group}, err
}

func lineNode(group string, proxies []string) (*yaml.Node, error) {
	var node yaml.Node
	err := node.Encode(map[string]any{"name": lineOf(group), "type": "select", "proxies": proxies, "hidden": true})
	return &node, err
}

func fastestGroupNode(spec fastestGroupSpec, proxies []string) (*yaml.Node, error) {
	var node yaml.Node
	if spec.Type == "select" {
		err := node.Encode(map[string]any{
			"name":    spec.Name,
			"type":    "select",
			"proxies": proxies,
		})
		return &node, err
	}
	url, interval, tolerance := spec.URL, spec.Interval, spec.Tolerance
	if url == "" {
		url = defaultFastestURL
	}
	if interval <= 0 {
		interval = defaultFastestInterval
	}
	if tolerance <= 0 {
		tolerance = defaultFastestTolerance
	}
	group := map[string]any{
		"name":      spec.Name,
		"type":      "url-test",
		"proxies":   proxies,
		"url":       url,
		"interval":  interval,
		"tolerance": tolerance,
	}
	// A captive or error page answers too; only the empty 204 is the node working.
	if strings.HasSuffix(url, "/generate_204") {
		group["expected-status"] = "204"
	}
	err := node.Encode(group)
	return &node, err
}

func offerLast(group *yaml.Node, name string) {
	entry := &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: name}
	proxies := resolveAlias(mappingValue(group, "proxies"))
	var content []*yaml.Node
	if proxies != nil && proxies.Kind == yaml.SequenceNode {
		content = append(content, proxies.Content...)
	}
	content = append(content, entry)
	setMappingValue(group, "proxies", &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq", Content: content})
}

func namesOf(items *yaml.Node) map[string]bool {
	names := map[string]bool{}
	if items == nil || items.Kind != yaml.SequenceNode {
		return names
	}
	for _, item := range items.Content {
		if name := nameOf(item); name != "" {
			names[name] = true
		}
	}
	return names
}

func nameOf(item *yaml.Node) string {
	item = resolveAlias(item)
	if item == nil || item.Kind != yaml.MappingNode {
		return ""
	}
	return scalarOf(mappingValue(item, "name"))
}

func scalarOf(node *yaml.Node) string {
	node = resolveAlias(node)
	if node == nil || node.Kind != yaml.ScalarNode {
		return ""
	}
	return node.Value
}

func deleteMappingValue(mapping *yaml.Node, key string) *yaml.Node {
	for i := 0; i+1 < len(mapping.Content); i += 2 {
		if name := mapping.Content[i]; name.Kind == yaml.ScalarNode && name.Value == key {
			value := mapping.Content[i+1]
			mapping.Content = append(mapping.Content[:i:i], mapping.Content[i+2:]...)
			return value
		}
	}
	return nil
}
