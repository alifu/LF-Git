# The engine: LFCore, LFKit and the `lfgit` CLI

All under `LFCore/` (a Swift package). Tests: `swift test --package-path LFCore`.

```
LFCore/Sources/
  LFCore/        C engine (lf_*.c, public header include/lfcore.h)
  LFKit/         Swift: wraps the engine, and is the git client the app uses
  LFGitCLI/      the `lfgit` command (ArgumentParser-style commands)
  lfgit/         main.swift of the CLI
  LFTestSupport/ GitFixture, Sandbox, ClassicProject for tests
  lf-bench/      benchmark
```

## C engine (`LFCore`)

| File | Role |
|---|---|
| `lf_scan.c` | one pass over a file: index line starts and find conflict markers (diff3 aware) |
| `lf_mmap.c`, `lf_buf.c`, `lf_map.c` | memory-mapped input (files over 4 GB work), growable buffers, maps |
| `lf_doc.c` | `lf_doc_open/close`, `lf_doc_get_conflict`, `lf_doc_line_offset`, `lf_doc_set_choice(_all)`, `lf_doc_set_custom` |
| `lf_resolve.c` | what text a choice produces for a conflict |
| `lf_save.c` | atomic save (temp file, fsync, rename), keeps permissions, encoding, BOM, line endings |
| `lf_textinfo.c` | binary / encoding / line-ending detection (`lf_detect_text`, `lf_probe_file`) |
| `lf_status.c`, `lf_error.c` | `lf_status` codes and per-thread `lf_last_error()` |
| `lf_pbx_*.c` | `project.pbxproj` lexer, parser, values and the object-by-object three-way merge (`lf_pbx_merge`) |

Rules (see the header): every fallible call returns an `lf_status`; handles are opaque; an `lf_doc` is not
thread-safe, so the app uses one document from one thread at a time (`EditorModel` documents the contract).

## `LFKit` (Swift)

| File | Role |
|---|---|
| `Git.swift` | runs the git binary: arguments, stdin, output to a file, allowed exit codes, timeouts, `Git.Side` checkout |
| `GitClient.swift` | **the** API: `status`, `stage`, `unstage`, `discard`, `commit`, `branches` (ahead/behind), log … |
| `GitStatus.swift` | `GitStatus`, `GitChange`, porcelain-v2 parser |
| `GitDiff.swift` | `diff(of:options:)`, `GitDiffFile`, `DiffParser`, `applyHunk` |
| `GitLinePatch.swift` | partial patches: `applyLines`, `discardLines`, `applyCommitLines`, `removeLines` |
| `GitBlame.swift`, `GitHistory.swift` | blame lines, log pages and filters, file history |
| `GitBranchOps.swift` | merge, rebase, reset, fast-forward, revert, cherry-pick, upstream, restore previous HEAD |
| `GitRemotes.swift`, `GitCredentials.swift`, `GitUserSettings.swift` | remotes, askpass-free credentials, user config |
| `GitStash.swift`, `GitTags.swift`, `GitWorktrees.swift`, `GitBisect.swift`, `GitRewrite.swift` | the matching areas |
| `GitCancellation.swift`, `Watchdog.swift` | stop a running command; time limits fire on their own thread |
| `LoginEnvironment.swift` | the user's login-shell environment, so hooks and credential helpers behave like in a terminal |
| `LFDocument.swift`, `LFTypes.swift`, `LFError.swift` | Swift wrappers over the C document, choices (`LFChoice`), errors |
| `PbxprojMerge.swift`, `ProjectRemerge.swift`, `MergeStrategy.swift` | project-file merging |
| `CustomCommand.swift` | user-defined commands from the config file |

Conventions: git is always run with fixed prefixes and no color; reading commands run freely, writing ones are
serialized by the **app** (`GitWriteQueue`), not by `LFKit`. Network commands have a timeout
(`defaultRemoteTimeout`) and never prompt for a password.

## `lfgit` CLI

`LFGitCLI` commands: `status`, `resolve` (`--all-current|incoming|both|base`, `--stage`), `tui` (interactive),
`install` (mergetool + merge driver), `open` (open in the app), `remerge`. `lfgit install --attributes '*.pbxproj'`
registers the project-file merge driver.

## Tests

`LFCore/Tests/LFCoreTests` (engine and `GitClient*Tests`), `LFCore/Tests/LFGitCLITests` (CLI). The app embeds the
same package, so engine changes are covered by both test targets.
