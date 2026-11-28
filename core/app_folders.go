package core

import (
	"regexp"
	"slices"
	"strings"
	"sync/atomic"

	"go.yaml.in/yaml/v3"
)

const appFoldersKey = "x-sloth-app-folders"

// An app is every program under its folder, a Mac's bundle or a Windows
// install directory, so helpers named unlike it and ones a later version adds
// take its route too. Case is ignored, as mihomo's own path rules do.
type appFolder struct{ prefix, app string }

type appFolders []appFolder

var (
	loadedFolders  appFolders
	currentFolders atomic.Pointer[appFolders]
)

// A Windows folder this near its drive would take in other apps.
const appFolderMinDepth = 3

func validAppFolder(folder string) bool {
	if strings.ContainsAny(folder, "\x00\r\n") || strings.TrimSpace(folder) != folder {
		return false
	}
	if strings.HasPrefix(folder, "/") {
		return strings.HasSuffix(strings.ToLower(folder), ".app/")
	}
	// A packaged app's folder ends before the version in its name.
	if !strings.HasSuffix(folder, `\`) && !strings.HasSuffix(folder, "_") {
		return false
	}
	parts := strings.FieldsFunc(folder, func(r rune) bool { return r == '/' || r == '\\' })
	return len(parts) >= appFolderMinDepth
}

func readAppFolders(root *yaml.Node) appFolders {
	var request map[string]string
	node := resolveAlias(deleteMappingValue(root, appFoldersKey))
	if node == nil || node.Decode(&request) != nil {
		return nil
	}
	var folders appFolders
	for app, folder := range request {
		if appPackagePattern.MatchString(app) && validAppFolder(folder) {
			folders = append(folders, appFolder{prefix: strings.ToLower(folder), app: app})
		}
	}
	// The longest goes first, so an app installed inside another's folder is itself.
	slices.SortFunc(folders, func(a, b appFolder) int {
		if len(a.prefix) != len(b.prefix) {
			return len(b.prefix) - len(a.prefix)
		}
		return strings.Compare(a.app, b.app)
	})
	return folders
}

func (f appFolders) appOf(path string) string {
	if path == "" {
		return ""
	}
	path = strings.ToLower(path)
	for _, folder := range f {
		if strings.HasPrefix(path, folder.prefix) {
			return folder.app
		}
	}
	return ""
}

// A comma would end the rule's payload early.
func (f appFolder) rule() string {
	return "PROCESS-PATH-REGEX,^" + strings.ReplaceAll(regexp.QuoteMeta(f.prefix), ",", `\x2c`)
}

// routedApp names the app a program counts as: the one whose folder holds it,
// else the program itself.
func routedApp(process, path string) string {
	if folders := currentFolders.Load(); folders != nil {
		if app := folders.appOf(path); app != "" {
			return app
		}
	}
	return process
}
