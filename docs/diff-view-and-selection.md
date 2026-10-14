# The diff view: selecting and copying text

One component draws every diff in the app (Changes, History, Branches, comparisons): `DiffTableView`.

## Pieces

| File | Role |
|---|---|
| `Changes/ChangesViews.swift` → `DiffContentView` | picks what to show: binary / not UTF-8 / empty / the table |
| `Changes/DiffTableView.swift` | `NSViewRepresentable` around an `NSTableView` with **one fixed-height row per diff line** |
| `Changes/DiffCells.swift` | `DiffLineCell` (blame column, old/new numbers, text) and `DiffHunkCell` (the `@@` row and its button) |
| `Changes/DiffControls.swift` | diff options menu, `changedLines`, `singleHunk`, `LineSelectionBar`, `CommitLineBar` |
| `LFKit/GitDiff.swift` | `GitDiffFile`: the diff written to a temp file and indexed; `text(ofLine:)`, `numbers(ofLine:)` |

Rows are read from the file **on demand** (`diff.text(ofLine:)`), so a huge diff costs memory only for visible rows.

## Selecting lines

* The table is always selectable (`selectionHighlightStyle = .regular`, `allowsMultipleSelection = true`): drag,
  ⇧-click for a range, ⌘-click to add, ⌘A for everything.
* Selected **rows** are reported to the owner as 1-based **diff line numbers** (`row + 1`) through the
  `selection: Binding<Set<Int>>` in `Coordinator.tableViewSelectionDidChange`. The binding is optional: a
  read-only diff (e.g. a comparison) selects and copies but reports nothing.
* The selection is cleared when another diff is shown (`Coordinator.show`).
* What the selection *means* depends on the screen: `LineSelectionBar` (stage lines), `CommitLineBar` (reuse
  lines of a commit). See [staging.md](staging.md).

## Copying (⌘C)

`DiffNSTableView` implements `copy(_:)` and asks its `onCopy` closure for the text of the selected rows;
`Coordinator.codeText(ofRows:)` produces it:

* the leading `+` / `-` / space column is dropped, so the clipboard holds code, not diff syntax;
* file headers (`diff --git`, `---`, `+++`) and `@@` hunk lines are left out, unless **only** those are selected
  (then they are copied as they are);
* `\ No newline at end of file` notes are left out;
* rows are joined with `\n`.

`DiffCopyTests` (`LF-GitTests/BranchesAndTreeTests.swift`) covers this on a real diff.

The conflict editor has its own table with the same idea: `ConflictNSTableView.copy` →
`ConflictTableView.Coordinator.text(ofRows:)`. See [conflict-editor.md](conflict-editor.md).

## Blame beside the diff

* `HistoryModel` loads `git blame` for the selected file at the selected revision together with the diff
  (`loadBlame`), skipping deleted files, and keeps `blameByLine` keyed by **new-side** line number.
* `DiffContentView(blame:showsBlame:)` passes it down; `DiffTableView.setBlame` reloads the table when it arrives.
* The blame column (190 pt, left of the line numbers) shows `shortHash author` only on the first line of a run from
  the same commit; the tooltip has the summary and date. Uncommitted lines say "not committed".
* The *Blame* checkbox is `@AppStorage("diff.showsBlame")` in `History/HistoryViews.swift`.

## Column layout

`EditorMetrics` (`Editor/ConflictCells.swift`) holds the shared row height, fonts and content width. The gutter width is
computed from the largest line number in the diff (`Coordinator.prepare`).

## Diff options

`DiffOptionsMenu` → `ChangesModel.setOptions` reloads the diff with *Ignore Whitespace*, *Detect Renames* and
more/less context. Ignoring whitespace or using 0 context makes the diff non-stageable (see
[staging.md](staging.md)).
