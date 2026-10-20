# Clone, reopen, close and the dashboard

How a repository gets into the window and out of it again. Code paths are relative to `LF-Git/Features/` (app) and
`LFCore/Sources/LFKit/` (engine).

## Clone

```
CloneSheet ──► CloneModel ──► CloneService ──► GitClone (probe / clone) ──► git
 (view)        (state machine)   (injectable)     (engine, no UI)
```

- **Engine** (`GitClone.swift`, `GitCloneRequest.swift`). `RemoteURL.parse` accepts `https`, `http`, `ssh`, `git@host:path`
  and `file`; it rejects a leading `-`, `ext::` and anything with whitespace, and takes a login typed into an https
  address out of it. `GitClone.probe` runs `git ls-remote --symref -- URL HEAD refs/heads/*` (8 s limit) and returns the
  branches, the default one first. `GitClone.clone` runs `git clone --progress` and reads progress from git's error
  output while it runs (`StandardErrorTailer`). A folder the clone created is removed if it fails or is cancelled; a
  folder that was already there is left alone. Every call passes `-c protocol.ext.allow=never`.
- **Logins.** A login typed in the sheet reaches git through a throw-away `GIT_ASKPASS` script that reads it from
  environment variables, so the password is never in a command line, the command log or a file. When "Remember in the
  keychain" is on, `GitAccountsModel.remember` stores it in git's credential helper (the same place as Settings ›
  Account).
- **Failures.** `RemoteFailure.classify` turns git's error text into `needsLogin`, `unreachable`, `notFound` or
  `other`. `unreachable` is what starts the VPN wait; a refused login is never retried automatically.
- **Model** (`Clone/CloneModel.swift`). States: `idle → probing → ready | needsLogin | waitingForNetwork`, then
  `cloning → done`. Typing waits 600 ms before asking the server; an answer for an address that was replaced is dropped
  (`generation`). While waiting for the network it retries after 3, 5, 8, then every 10 seconds, and straight away when
  `NWPathMonitor` reports the network is back. `CloneService` is injected, so `CloneModelTests` run without a process.
- **Sheet** (`Clone/CloneSheet.swift`, `CloneCredentialForm.swift`). The folder is always asked for: nothing is
  defaulted or remembered. Clone is only offered on the dashboard and in File when no repository is open.

## Reopen and close

- `AppModel.lastOpenedRepository` and `recentRepositories` (20) live in `UserDefaults`. Scratch folders (temporary
  directories) are never remembered, so tests cannot become "last".
- `AppModel.restoreLastRepository` runs at launch when no `--repo` argument was given. It is skipped by the setting
  *Settings › General › Reopen the last repository when the app starts* or by the `-LFNoRestore` launch argument (the UI
  tests use it). A folder that has gone is dropped from the recents and explained on the dashboard (`restoreNote`).
- `AppModel.close()` (File › Close Repository, ⇧⌘W, the toolbar button, the palette) asks about unsaved resolutions,
  calls `RepositoryModel.shutDown()` (stops the watcher and the running command, and makes a refresh still in flight
  drop its result) and forgets the last repository.

## Dashboard

`Welcome/DashboardView.swift` replaces the old welcome screen. Open and Clone cards, a *Needs attention* strip (conflicts
or an unfinished merge/rebase), the last repository with an Open button, the other recents (searchable above 8), and
the conflict preview as a small card.

The chips come from `RepositorySummary` (`Welcome/RepositorySummary.swift`): one `git status --porcelain=v2 --branch`
per repository, **counted, not parsed into a list**, so a folder with a hundred thousand changes costs one pass over
the text. At most three run at once, each with a 2 s limit; the rows show their name and path at once and the chips fill
in as they arrive. A repository that does not answer simply shows no chip.

## Tests

| Area | Where |
|---|---|
| addresses, progress, failure classes, probe, clone, cleanup, cancel | `LFCore/Tests/LFCoreTests/GitCloneTests.swift` |
| sheet logic with a scripted server | `LF-GitTests/CloneModelTests.swift` |
| reopen, close, recents | `LF-GitTests/AppModelRestoreTests.swift` |
| dashboard summaries | `LF-GitTests/RepositorySummaryTests.swift` |
| sheet, dashboard and close in the real app | `LF-GitUITests/CloneAndDashboardUITests.swift` |

The UI tests cannot drive the macOS folder chooser, so an actual clone through the sheet is covered by the engine and
model tests instead.
