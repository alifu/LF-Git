# LF-Git code guide

Where things live, and how a user action travels from a click to a git command. The user-facing description is in
the [top-level README](../README.md); these pages are for people changing the code.

| Page | Read it for |
|---|---|
| [architecture.md](architecture.md) | the layers, the models, how an action runs, how the window follows git |
| [staging.md](staging.md) | stage / unstage a file, a folder, a hunk or single lines; the Space key |
| [diff-view-and-selection.md](diff-view-and-selection.md) | the diff table, selecting and copying lines, blame beside the diff |
| [changes-panel.md](changes-panel.md) | the Changes sidebar: sections, folder tree, multi-select, commit box |
| [branches-and-history.md](branches-and-history.md) | branch lists, search, ahead/behind badges, branch menu, history, confirmations |
| [conflict-editor.md](conflict-editor.md) | the conflict table, choices, Edit box, copy, binary files |
| [engine.md](engine.md) | `LFCore` (C engine), `LFKit` (git client), `lfgit` CLI |
| [shell-ui.md](shell-ui.md) | section ribbon, toolbar, command palette, shortcuts, dialogs |
| [testing.md](testing.md) | which tests cover what, how to run them, known quirks |

## "Where is the code for …?"

| I want to change … | Start here |
|---|---|
| what Space does in the file list | `Changes/ChangesSidebar.swift` → `toggleStage()` |
| what Space does in the diff | `Changes/ChangesViews.swift` → `stageSelectedLines` |
| the *Stage Hunk* button | `Changes/DiffCells.swift` (`DiffHunkCell`), `ChangesViews.swift` → `hunkAction` |
| staging single lines | `LFKit/GitLinePatch.swift` → `partialPatch`, `applyLines` |
| selecting lines in a diff | `Changes/DiffTableView.swift` (`selection`, `tableViewSelectionDidChange`) |
| copying lines (⌘C) | `DiffNSTableView.copy`, `Coordinator.codeText` (diff); `ConflictNSTableView.copy` (conflicts) |
| the Stage / Unstage button on a row | `ChangesSidebar.swift` → `ChangeRow` |
| `git add` / `git restore --staged` | `LFKit/GitClient.swift` → `stage`, `unstage` |
| discarding changes | `GitClient.discard`, `LineSelectionBar` (lines), `ChangesSidebar.swift` (files) |
| the branch list and its search | `Branches/BranchesViews.swift` |
| the toolbar branch menu and its search | `Repository/RepositoryToolbar.swift` → `BranchMenu` |
| "Are you sure?" dialogs | `RepositoryModel+Actions.swift`, `Branches/BranchContextMenu.swift`, `History/CommitContextMenu.swift` |
| the ribbon | `Repository/SectionRibbon.swift` |
| accepting current / incoming / both | `Editor/EditorModel.swift` → `resolve`, `resolveAll` |
| the Edit box | `Editor/EditConflictView.swift`, `EditorModel.edit` |
| image / PDF conflicts | `Editor/BinaryFileView.swift`, `BinaryPreview.swift`, `BinaryVersion.swift` |
| the merge engine | `LFCore/Sources/LFCore/*.c`, header `include/lfcore.h` |

Paths are relative to `LF-Git/Features/` for the app and `LFCore/Sources/` for the engine and git client.
