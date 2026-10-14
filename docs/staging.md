# Staging and unstaging

Everything that moves changes between *Changes* (work tree) and *Staged* (index).

## Layers

| Level | UI | Model call | Git command (in `LFKit/GitClient.swift`) |
|---|---|---|---|
| Whole file(s) | row button, context menu, **Space**, header buttons | `ChangesModel.stage(_:)` / `unstage(_:)` | `git add -- paths` / `git restore --staged -- paths` |
| Everything | *Stage All* / *Unstage All* | `stageAll()` / `unstageAll()` | `git add .` / unstage `.` |
| Folder | folder row button, context menu, **Space** on the selected folder (tree view) | `stage` / `unstage` with every file below it | same as files |
| Discard a folder | folder row button or context menu → *Discard Changes in Folder…* (Changes side only) | `discard(_:)` with every file below it | `git restore` / `git clean` (after a confirmation) |
| One hunk | *Stage Hunk* / *Unstage Hunk* on the `@@` row | `applyHunk(_:of:)` | `git apply --cached [--reverse]` with a one-hunk patch |
| Selected lines | *Stage Lines* bar, **Space** in the diff | `applyLines(_:in:of:)` | `git apply --cached [--reverse]` with a partial patch |
| Discard lines | *Discard Lines…* | `discardLines(_:in:of:)` | reverse patch applied to the work tree |
| Discard file | context menu *Discard Changes…* | `discard(_:)` | `git restore` (tracked) / `git clean` (untracked) |

`unstage` before the first commit uses `git rm --cached -r -q -f` because `HEAD` does not exist yet.
A renamed file needs **both** paths to unstage (`ChangesModel.unstage(_ change:)` adds `originalPath`).

## The Space key

* **File list** (`ChangesSidebar.toggleStage`): acts on every selected row. Rows in *Changes* are staged, rows in
  *Staged* are unstaged, in one call each. Afterwards `picked` moves to the rows' new side so a second Space
  undoes the first. A selected folder row (`ChangeSelection.isFolder`) stands for every changed file below it
  (`selectedFiles()`); selecting a folder does not change the diff on screen.
* **Diff** (`ChangesDetailView.stageSelectedLines`, wired through `DiffContentView.onSpace` →
  `DiffNSTableView.onSpace`): if lines are selected and they sit in one hunk, stage those lines; otherwise stage or
  unstage the **whole file**.
* `DiffNSTableView.keyDown` only treats a bare space as the shortcut (no ⌘ ⌃ ⌥).

## Hunk staging

1. `DiffTableView` shows a button on every hunk header row (`DiffHunkCell`) when a `HunkAction` is supplied.
2. `ChangesDetailView.hunkAction` supplies it only when it is safe: the loaded diff belongs to the selected row,
   no git command is running, the change is an ordinary modification, and the diff `isStageable`.
3. `GitDiffFile.patch(for:)` builds *file header + hunk bytes* — a patch `git apply` accepts alone.
4. `GitClient.applyHunk(_:of:stage:)` pipes it to `git apply --cached` (with `--reverse` to unstage).

`GitDiffFile.isStageable` is false when whitespace is ignored or context is 0: such a diff does not match the file
byte for byte, so it cannot be turned back into a patch.

## Line staging

`LFKit/GitLinePatch.swift` builds a patch that contains only the selected lines of **one** hunk
(`partialPatch(of:in:selecting:reverse:)`):

| | unselected `+` line | unselected `-` line |
|---|---|---|
| Stage (forward) | left out | kept as context |
| Unstage / discard / revert (reverse) | kept as context | left out |

Line numbers are 1-based diff line numbers (table row + 1). Header counts (`@@ -a,b +c,d @@`) are recomputed from
what remains. A brand-new file is staged line by line after `git add --intent-to-add`.

`GitDiffFile.changedLines(in:)` (in `Changes/DiffControls.swift`) drops selected rows that are not real `+`/`-`
lines, and `singleHunk(containing:)` returns the hunk they all belong to — nil if they span several, which the
UI reports as "Pick lines inside a single hunk."

`LineSelectionBar` (same file) is the strip above the diff: the instruction text, the *Stage/Unstage Lines*
button (`stage-lines`), *Discard Lines…* (`discard-lines`, confirmed) and *Clear*.

## Reusing lines of old commits

`CommitLineBar` + `GitClient.applyCommitLines(_:in:of:to:reverse:)` apply or revert selected lines of a commit's
diff to the work tree, the index or both (`PatchTarget`). `removeLines(_:in:of:from:)` rewrites history to cut
lines out of a commit (only on the checked-out branch, work tree clean, confirmed first).

## Tests

* `LFCore/Tests/LFCoreTests/GitClientLineTests.swift` — partial patches, staging/unstaging/discarding lines.
* `LFCore/Tests/LFCoreTests/GitClientStatusTests.swift` — stage / unstage / discard.
* UI: `LazygitUITests.testSpaceStagesAndUnstagesTheSelectedFile`,
  `testStageThenUnstageWithTheButtonsLeavesNoStaleRow`; `GitClientUITests.testStageOneHunkAndCommit`.
