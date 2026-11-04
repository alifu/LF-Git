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

## Three columns (Settings › Layout › Lists)

`layout.lists` (`ListsLayout`) is **Classic** (default) or **Three columns** (`threeColumn`). Classic is described
above. Three columns affects Branches, History, Stash, Tags and Reflog:

```
Branches                                        History, Stash, Tags, Reflog
┌ branches list ─────┐ ┌ one card ─────────────────────────┐   ┌ list (sidebar) ┐ ┌ one card ───────────────────┐
│ ◎ current target   │ │ commits, day headers │ preview     │   │ commits (day   │ │ files │ diff + blame│
│ [All|Local|Remote] │ │ Today                │ files │ diff│   │ headers) …     │ │       │             │
│ search             │ │ ● commit …           │             │   └────────────────┘ └───────────────────────────┘
│ Local · Remote     │ │ Yesterday            │             │
└────────────────────┘ └───────────────────────────────────┘
```

* **Branches** (`BranchesSidebar`): a pinned **current target** row above the search (`current-target`): the checked-out
  branch (or *Detached HEAD* / *No branch yet*), *tracks …* or *no upstream*, and its ahead/behind badge. It is not
  a selectable row. A segmented **All / Local / Remote** picker (`branch-scope`) filters the groups; Classic always
  shows both.
* **Branches detail** (`BranchesDetail`): one card (`JoinedCards`) with the commit list on the left and the preview on
  the right. The commit list (300–420 pt) is `CommitListView` with day headers. The preview is `HistoryDetailView`, with
  nothing selected it shows *Select something to preview* on the dot grid. Classic is a `HSplitView` instead.
* **History**: the list is the filtered commit list with day headers in its own card (`HistorySidebar`). The detail is
  `HistoryDetailView` with files │ diff side by side in one card, the file column 180–320 pt. Classic stacks the file
  list above the diff.
* **Stash, Tags and Reflog** keep their list. Their detail is `CommitViewerDetail`, which uses `HistoryDetailView`, so
  they get the same files │ diff.
* The commit preview on the Lanes canvas (Changes) is always stacked (`forcesStacked`), because 440 pt is too narrow
  for two columns.
* Day headers come from `DayGrouping.group` (one pass over the commits already in order): *Today*, *Yesterday*, then
  the date. The groups are rebuilt only when the commits change or the layout is switched.

## Reflog timeline (Settings › Layout › Reflog)

`layout.timeline` (off by default) turns the Reflog list into a timeline (`ReflogSidebar`, `TimelineRow`):

* Entries are grouped by day (`ReflogTimeline`, rebuilt only when the reflog changes). Each day is a section.
* Each row has a time column (56 pt), a connector line that is cut at the first and last entry of a day, and a dot.
  The dot of the current HEAD entry is accent-coloured and marked **Current** (`reflog-current`).
* Off, the Reflog is the plain list as before. The context menu and the selection are the same in both.

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
