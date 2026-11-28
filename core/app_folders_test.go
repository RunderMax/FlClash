package core

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/metacubex/mihomo/constant"
)

func TestLoadSetupConfigRoutesEveryProgramUnderAnAppsFolder(t *testing.T) {
	home := t.TempDir()
	previous := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() { constant.SetHomeDir(previous) })
	profile := `proxies:
  - {name: a, type: socks5, server: 127.0.0.1, port: 1080}
proxy-groups:
  - {name: g, type: select, proxies: [a]}
rules:
  - MATCH,g
x-sloth-app-routes: {at: 0, routes: {Google Chrome: a, Chrome Helper: DIRECT, Idle: a}}
x-sloth-app-folders:
  Google Chrome: "/Applications/Google Chrome.app/"
  Unrouted: "/Applications/Unrouted.app/"
  Idle: "/"
`
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(profile), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	cfg, err := loadSetupConfig(&SetupParams{})

	if err != nil {
		t.Fatalf("loadSetupConfig = %v", err)
	}
	want := []string{
		"ProcessName,Google Chrome,a",
		"ProcessName,Chrome Helper,DIRECT",
		"ProcessName,Idle,a",
		`ProcessPathRegex,^/applications/google chrome\.app/,a`,
		"Match,,g",
	}
	if got := ruleLines(cfg); !reflect.DeepEqual(got, want) {
		t.Fatalf("rules = %v, want %v", got, want)
	}
	helper := &constant.Metadata{
		Process:     "Google Chrome Helper",
		ProcessPath: "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper",
	}
	if matched, target := cfg.Rules[3].Match(helper, constant.RuleMatchHelper{}); !matched || target != "a" {
		t.Errorf("the helper matched = %v to %q, want the app's route", matched, target)
	}
	other := &constant.Metadata{Process: "Other", ProcessPath: "/Applications/Google Chrome.app.bak/Other"}
	if matched, _ := cfg.Rules[3].Match(other, constant.RuleMatchHelper{}); matched {
		t.Error("a program beside the folder took the app's route")
	}
}

func TestAppFoldersNameTheAppWhoseFolderHoldsAProgram(t *testing.T) {
	folders := appFolders{
		{prefix: `c:\apps\suite\tool\`, app: "tool.exe"},
		{prefix: `c:\apps\suite\`, app: "suite.exe"},
	}
	cases := map[string]string{
		`C:\Apps\Suite\bin\helper.exe`:  "suite.exe",
		`C:\Apps\Suite\Tool\worker.exe`: "tool.exe",
		`C:\Apps\Suite2\a.exe`:          "",
		"":                              "",
	}
	for path, want := range cases {
		if got := folders.appOf(path); got != want {
			t.Errorf("appOf(%q) = %q, want %q", path, got, want)
		}
	}
}

func TestAppFolderRuleKeepsACommaOutOfThePayload(t *testing.T) {
	rule := appFolder{prefix: "/applications/a, b (1).app/"}.rule()
	if want := `PROCESS-PATH-REGEX,^/applications/a\x2c b \(1\)\.app/`; rule != want {
		t.Errorf("rule = %q, want %q", rule, want)
	}
}

func TestValidAppFolderRefusesWhatWouldTakeInOtherApps(t *testing.T) {
	cases := map[string]bool{
		"/Applications/Muse.app/": true,
		`C:\Program Files\App\`:   true,
		"/Applications/Muse.app":  false,
		"/":                       false,
		`C:\`:                     false,
		"/Applications/":          false,
		"/Users/me/":              false,
		`C:\Program Files\WindowsApps\OpenAI.ChatGPT_`: true,
		`C:\Program Files\`:                            false,
		" /Applications/Muse.app/":                     false,
		"/Applications/Mu\nse.app/":                    false,
	}
	for folder, want := range cases {
		if got := validAppFolder(folder); got != want {
			t.Errorf("validAppFolder(%q) = %v, want %v", folder, got, want)
		}
	}
}

func TestRoutedAppIsTheProgramItselfOutsideEveryFolder(t *testing.T) {
	folders := appFolders{{prefix: "/applications/muse.app/", app: "Muse"}}
	currentFolders.Store(&folders)
	t.Cleanup(func() { currentFolders.Store(nil) })

	if got := routedApp("Muse Helper", "/Applications/Muse.app/Contents/MacOS/Muse Helper"); got != "Muse" {
		t.Errorf("a helper = %q, want its app", got)
	}
	if got := routedApp("curl", "/usr/bin/curl"); got != "curl" {
		t.Errorf("a loose program = %q, want itself", got)
	}
}
