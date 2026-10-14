# The conflict editor

`Editor/` — the merge tool itself. Rows come from the C engine on demand, so a 2,000,000-line file opens in seconds.

## Pieces

| File | Role |
|---|---|
| `EditorModel.swift` | per-conflict state: choice, custom text, focus, undo/redo, save |
| `ConflictTableView.swift` | the table (`NSTableView`, one row per line) and its coordinator; double-click, ⌘C |
| `ConflictCells.swift` | `EditorMetrics`, row views, the header row with the accept buttons |
| `LineRole.swift` | what a line is: normal, marker, current/incoming/base body, resolved… |
| `EditorView.swift` | toolbar (Current / Incoming / Both / Edit…, Open in Editor), compare sheet, save, Re-merge Project |
| `EditConflictView.swift` | the Edit box: type, paste, copy a side, "Add to Result" |
| `CompareView.swift`, `MinimapView.swift` | side-by-side compare, conflict map |
| `SyntaxHighlighter.swift` | token colors for code lines |
| `BinaryFileView.swift` (+ `BinaryPreview`, `BinaryVersion`) | binary conflicts |

## Choices

`LFChoice`: `unresolved, current, incoming, bothCurrentFirst, bothIncomingFirst, base, custom`.

* `EditorModel.resolve(_:as:)` sets one conflict; `resolveAll(as:)` sets every conflict as **one** undo step
  (base skips conflicts without a base).
* `edit(_:text:)` stores the user's text and switches the conflict to `custom`. The text is kept per conflict
  (`customTexts`), so reopening Edit shows it. `initialEditText` starts from the earlier text or both sides.
* A Windows-style file keeps its `\r\n`: the box shows `\n` and `fileText(_:)` converts back.
* `undo()` / `redo()` replay `Change` entries; ⌘Z / ⇧⌘Z are in `AppCommands.swift`.
* Keyboard: ⌘1…⌘4 accept current/incoming/both/base, ⌥⌘↓/↑ next/previous conflict, ⌘S save.

## Selecting and copying

* `ConflictTableView.makeNSView` enables multi-row selection (drag, ⇧-click, ⌘A).
* `ConflictNSTableView.copy(_:)` (⌘C) calls `onCopy`, which is `Coordinator.text(ofRows:)`.
* Double-clicking a line of a conflict opens its Edit box (`doubleClicked` → `onEdit`).
* The engine edits **conflict regions only**; lines outside conflicts cannot be changed in the app.
  *Open in Editor* opens the file in the default editor and the window follows the change (the repository
  watcher refreshes).

## Saving

`EditorModel.save()` writes the file on a background thread (`lf_doc_save`: temp file, fsync, rename, keeping
permissions, encoding, BOM, line endings) while every mutation is blocked (`isSaving`). When no conflict is left
it stages the file (`git add`). Unresolved conflicts stay as markers.

## Binary files

`RepositoryModel.scan` classifies a conflicted file with `LFFileProbe`; binary ones show `BinaryFileView`.

1. `BinaryFileView.version(stage:path:root:)` reads index stage 2 (current) and 3 (incoming) with
   `git show :N:path` off the main thread.
2. `BinaryVersion.classify(_:)` decides the kind from **content**: PDF header → `.pdf`, decodable by `NSImage`
   → `.image`, nothing → `.missing` (that side deleted the file), otherwise `.other`.
3. `BinaryPreview` shows the image, a `PDFPreview` (PDFKit: scroll, zoom, select text) or the file-type icon.
   Images can be compared side by side or with the **Swipe** slider (`ImageSwipeView`).
4. *Use Current / Use Incoming* → `RepositoryModel.takeSide(_:of:)` → `git checkout --ours/--theirs` and
   `git add`. *Open…* writes the version to a temporary folder and opens it, leaving the work tree alone.

## Project files

`project.pbxproj` conflicts offer *Re-merge Project* (`RepositoryModel.remergeProject`), which merges object by
object with the C engine (`lf_pbx_merge`) — see [engine.md](engine.md).

## Tests

`LF-GitTests/ConflictEditTests.swift`, `ModelTests.swift` (binary side, editor load), `LFCore/Tests/LFCoreTests/`
(`DocumentTests`, `PropertyTests`, `PbxprojMergeTests`), `LF-GitUITests/ConflictResolutionUITests.swift`.
