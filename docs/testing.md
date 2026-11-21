# Testing

| Target | Where | Covers |
|---|---|---|
| Engine and git client | `LFCore/Tests/LFCoreTests` | C engine, `GitClient*` (status, staging, lines, branches, history, stash, refs), pbxproj merge, properties |
| CLI | `LFCore/Tests/LFGitCLITests` | `lfgit` commands |
| App models | `LF-GitTests` (Swift Testing) | models, PathTree, branch section, binary versions, diff copy, launch options, theme |
| App UI | `LF-GitUITests` (XCTest) | whole-window flows against a temp repository |

## Commands

```bash
swift test --package-path LFCore                                   # engine + CLI
xcodebuild test -scheme LF-Git -destination 'platform=macOS' -only-testing:LF-GitTests
xcodebuild test -scheme LF-Git -destination 'platform=macOS' -only-testing:LF-GitUITests/LazygitUITests
```

## Writing tests

* New behaviour starts with a test. Engine behaviour: add to the matching `GitClient*Tests` using `GitFixture`
  (`LFTestSupport`), which builds a real repository in a temp folder.
* Model tests open a fixture with a small private `openRepository(_:)` helper (see `LazygitFeatureTests`) and await the model's calls.
* A view's pure logic should live in a testable type (`PathNode`, `BinaryVersion.classify`, `parseTrack`,
  `Coordinator.codeText`), not inside the view body.

## UI tests

* `GitUITestCase` creates the repository (`repository`), launches the app with `--repo <path> -appearance <mode>`,
  and provides `write`, `git`, `waitUntil`, `showSection`, `attachScreenshot`.
* The UI test runner is sandboxed and cannot run `/usr/bin/git`; the helper calls a real git executable.
* Find things by accessibility identifier: `app.descendants(matching: .any)["change-staged-a.txt"]`.
* A SwiftUI **popover** (the toolbar branch menu) is not visible to XCUITest; drive it with the keyboard.
* Alerts with a text field are sheets on macOS (`app.sheets.textFields`).
* Files the runner writes are quarantined, and git refuses to run a quarantined hook ("cannot exec"). Keep hook
  scripts as fixtures in the source tree and point `core.hooksPath` at them (`PushHooksUITests`,
  `Fixtures/guardrail-hooks`).
* The Push pill is a pop-up button: clicking its middle can open its menu. Press ⌥⌘P to push.

## Known quirks

* `LazygitUITests.testSettingsHasTabsForAccountNetworkEnvironmentAndTheme` fails on the unchanged baseline
  (pre-existing).
* "Timed out while enabling automation mode" means the test runner cannot control the UI: unlock the screen and
  accept any macOS automation prompt, then rerun.
* In a full run the heavy `testTwoMillionLineFile` can be followed by "Failed to terminate" errors in other tests;
  they pass when rerun alone.
* A Swift 6.2 compiler crash is worked around in `ChangesSidebar.pick` (see [changes-panel.md](changes-panel.md)).
* Building the `lfgit` or `lf-bench` scheme in Xcode compiles LFKit as plain objects and leaves
  `LFKit.swiftmodule` in the shared `Products/Debug` folder, where it would shadow the `LFKit.framework` module the
  app uses (new LFKit API then looks missing: "extra argument", "cannot find … in scope"). The app target's first
  build phase, *Remove stale LFKit module*, deletes it before compiling; the build log says when it did.

## Release checks

`Scripts/release/check-version.sh` keeps the version in `MARKETING_VERSION`, `lfcore.h` and `Formula/lfgit.rb`
aligned; `RELEASING.md` has the tag → build → cask flow.
