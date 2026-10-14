# Architecture

```
SwiftUI views ──▶ @Observable models ──▶ LFKit (GitClient, Git) ──▶ git binary
   (LF-Git/)         (RepositoryModel,        (Swift package           (and the C engine
                      ChangesModel,            LFCore/Sources/LFKit)    LFCore for merges)
                      HistoryModel,
                      EditorModel)
```

* **Views** only draw and forward intent. Anything that touches git goes through a model.
* **Models** are `@Observable` classes on the main actor. They never block it: git work runs in `@concurrent`
  static functions or in the write queue.
* **`LFKit`** is the Swift package that talks to git (`GitClient`, `Git`) and wraps the C engine (`LFDocument`).
  It has no UI and is also used by the `lfgit` command line tool.
* **`LFCore`** is the C engine that opens huge conflicted files, finds conflict markers and writes the result.

## The models

| Model | File | Owns |
|---|---|---|
| `AppModel` | `App/AppModel.swift` | the open repository, recent list, the error alert; `run { }` and `report(_:)` |
| `RepositoryModel` | `Repository/RepositoryModel.swift` (+`+Actions`, `+Bisect`) | status, branches, stashes, tags, remotes, reflog, conflicted files, one `EditorModel` per file, the write queue, the activity log, pending dialogs |
| `ChangesModel` | `Changes/ChangesModel.swift` | selected change, the loaded diff, commit message, amend, stage/unstage/hunk/line calls |
| `HistoryModel` | `History/HistoryModel.swift` | a page of commits, the selected commit, its files, its diff and blame (one instance for History, one for Branches) |
| `EditorModel` | `Editor/EditorModel.swift` | one conflicted file: per-conflict choices, undo/redo, focus, save |

## How an action runs

1. A view calls `app.run { try await … }`. `AppModel.run` shows any error in an alert (a cancelled command is not
   an error).
2. The work calls a model method, e.g. `changes.stage(["a.txt"])`.
3. Model methods that **write** go through `RepositoryModel.writeQueue` (`GitWriteQueue`, an actor), so two git
   writes never collide on `index.lock`. `ChangesModel.mutate` and `RepositoryModel.perform` both do this.
4. `RepositoryModel.perform(title, cancellable:, serialized:)` also shows the title in the toolbar, logs
   Started / Finished / Failed to the activity log, and treats "stopped on conflicts" as success (the banner
   takes over). Network commands pass `serialized: false` so staging still works during a long fetch.
5. After the write, `refresh()` reads git again. The newest refresh wins; an older, slower one is dropped.

## How the window follows git

* `refresh()` takes a `RepositorySnapshot` (status, branches, stashes, tags, remotes, reflog, worktrees, submodules,
  conflicted files) **off the main thread**, publishes it, then calls `changes.statusDidChange` and
  `history.repositoryDidChange`.
* `RepositoryWatcher` (FSEvents) calls `refresh()` 0.6 s after files change, ignoring `.git/objects`, `DerivedData`
  and similar noise. Only the real window starts it (`startWatching`), so tests stay predictable.
* `ChangesModel.statusDidChange` keeps the selection on the same file when it moves between *Staged* and
  *Changes*, and reloads the diff only when the change itself differs (or `reloadDiff` asks for it).

## Staleness guards

Several places carry a "generation" or identity check so a slow result cannot overwrite a newer one:

* `RepositoryModel.refreshGeneration`, `ChangesModel.diffGeneration`, `HistoryModel` generation for blame.
* `ChangesModel.applyHunk/applyLines/discardLines` require `diff === self.diff`: a hunk's byte offsets are only
  valid for the diff they came from.

## Conventions

* Immutable value types for data crossing threads (`Sendable`); models mutate their own state only on the main actor.
* Files stay small (a soft 800-line ceiling); the largest is `RepositoryModel.swift`.
* Colors come from `Design/theme.json` through `LFThemeToken`; views use `.theme(.token)`.
* Accessibility identifiers (`stage-<path>`, `change-staged-<path>`, `section-<Name>`, …) are what UI tests find;
  keep them stable.
