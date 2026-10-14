# Branches, history and confirmations

## Branches section

`Branches/BranchesViews.swift` — `BranchesSidebar` (left) and `BranchesDetail` (commit list + commit detail).

* **Local / Remote sections** are collapsible (`Section(isExpanded:)`). Remote names drop the `origin/` prefix:
  `remoteName(of:)` finds the longest known remote that prefixes the name, `nameOnRemote` is the rest. With more
  than one remote each gets a `DisclosureGroup`; with one, its branches stand alone.
* **Folders**: `feature/login` becomes a folder via `PathNode` (`BranchTreeRows`). Folder open/closed state shares
  the `collapsed` set with the sections; keys are prefixed (`local:`, `remote:<name>:`) so two trees never clash.
* **Search**: `query` filters both lists by case-insensitive substring and switches to a flat result list
  (folders hidden); `ContentUnavailableView.search` shows when nothing matches.
* **Expand All / Collapse All**: `collapsed = []` / `collapsed = Set(allKeys)`.
* **Double-click = check out**: `.contextMenu(forSelectionType:menu:primaryAction:)`; the primary action calls
  `checkOut(_:)` → `GitClient.switchBranch` (a remote branch gets a local tracking branch). The menu is
  `BranchContextMenu`.
* **Pull/push badges**: `TrackingBadge(ahead:behind:)` on local rows. `GitClient.branches()` reads
  `%(upstream:track,nobracket)` and `GitClient.parseTrack` turns `ahead 2, behind 1` into numbers. They are as of
  the last fetch.
* **Selecting a branch** shows its history: `showHistory()` → `repository.branchHistory.show(.log(revision:))`.

## History

`History/HistoryModel.swift` (state), `HistoryViews.swift` (lists and detail), `GraphView.swift` (lanes),
`CommitContextMenu.swift`.

* `HistoryModel` pages commits (`loadMore`), keeps the selected commit and its files, loads the diff and the blame
  for the selected file (`selectFile`, `loadBlame`).
* `reload()` always selects the newest commit if the selection is missing, so the detail pane is never empty after
  choosing a branch. `show(_:)` resets the selection only when the revision changes (or on first load), so a
  refresh keeps the user's commit.
* `HistoryDetailView` always lays out its panes (header, file list, diff); with nothing selected it shows an empty
  header and placeholder text instead of collapsing to half the view.
* Comparisons (`compare(from:to:)`) use `GitClient.diff(of: .range(...))`.

## Toolbar branch menu

`Repository/RepositoryToolbar.swift` → `BranchMenu`: a button that opens a **popover** with a search field
(focused on open), Local and Remote lists, **New Branch…** and a **Delete Branch** menu. Return switches to the first
match. It is a popover because a SwiftUI `Menu` cannot hold a text field. XCUITest cannot see inside the popover, so
`GitClientUITests.testSearchTheBranchMenuAndSwitch` drives it with the keyboard.

## Confirmations

All dialogs share `PendingConfirmation` (`Repository/RepositoryModel.swift`) and `repository.confirm(_:)`, which
`RepositoryDialogs.swift` presents as a `confirmationDialog`. `isDestructive` picks the button role.

| Action | Where the question is built |
|---|---|
| merge (each mode), rebase onto, fast-forward, reset (all modes) | `Branches/BranchContextMenu.swift` |
| pull and merge / pull and rebase | `RepositoryModel+Actions.swift` → `requestPull` (toolbar, palette) |
| paste (cherry-pick) | `RepositoryModel+Actions.swift` → `requestPaste` |
| squash, fixup, autosquash, reset, drop, reword… | `History/CommitContextMenu.swift` |
| discard changes / lines / everything | `ChangesSidebar.swift`, `LineSelectionBar`, `PaletteActions.swift` |
| force push | `PaletteActions.swift`, `RepositoryToolbar.swift` |

To add a confirmation: build a `PendingConfirmation(title:message:confirmTitle:){ app.run { … } }` and pass it to
`repository.confirm`. Name the action and the branches in the title ("Rebase 'feature' onto 'main'?").
A plain fast-forward pull is not confirmed.

## Tests

`LF-GitTests/BranchesAndTreeTests.swift` (auto-select, blame beside the diff, ahead/behind, pull confirmation),
`LFCore/Tests/LFCoreTests/GitClientHistoryTests.swift` (ahead/behind parsing),
`LazygitUITests` (merge confirmation, double-click checkout, branch search).
