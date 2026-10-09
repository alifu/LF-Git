# LF-Git

A native macOS merge tool and Git client for resolving conflicts in **files of any size**, from a Swift source file to an Xcode `project.pbxproj` with millions of lines.

> **Status:** early development. The C engine, the `lfgit` command line tool, the semantic `.pbxproj` merge and the macOS app, including a Git client, work (phases 1–5); Homebrew packaging is next.

## Goals

- Resolve conflicts in **any text file** (Swift, JSON, YAML, `.strings`, lock files, `.pbxproj`, …), keeping encoding and line endings byte-exact.
- Stay fast on huge files: memory-mapped, indexed, and streamed by a C11 engine.
- VSCode-style resolution: **Accept Current / Accept Incoming / Accept Both / Edit**, with keyboard navigation.
- Smart merge strategies, starting with a semantic `.pbxproj` 3-way merge that auto-resolves most project-file conflicts.
- Light and dark mode, with a green theme built on the [Atlassian Design color palette](https://atlassian.design/foundations/color/color-palette).

## Layout

| Path | What |
|---|---|
| `LF-Git.xcodeproj`, `LF-Git/` | SwiftUI macOS app |
| `LFCore/` | Swift package: C engine (`LFCore`), Swift wrapper (`LFKit`), CLI (`lfgit`) |
| `Design/theme.json` | Theme source of truth (palette + light/dark tokens) |
| `LFCore/Scripts/` | Theme generator, synthetic conflict generator |

## Build

Requirements: macOS 14+, Xcode 26 (Swift 6).

```bash
# Engine + CLI
swift build --package-path LFCore
swift test --package-path LFCore
swift run --package-path LFCore lfgit --version

# App
xcodebuild -project LF-Git.xcodeproj -scheme LF-Git build
```

## The app

The window has three sections: **Changes**, **History** and **Conflicts**.

**Changes** lists staged and unstaged files. Select one to see its diff with old/new line numbers; stage or
unstage the whole file, or just **one hunk** (Stage Hunk / Unstage Hunk on the `@@` row). Write a message and
**Commit**, or tick *Amend last commit*. Discarding an edit asks first.

**History** shows the commit log with a branch graph, paged as you scroll, for the current branch or all
branches. Select a commit to see its files and the diff of each.

**Toolbar:** a branch menu (switch, create, delete, remote branches become tracking branches), **Fetch**, **Pull**
(fast-forward only, merge or rebase) and **Push** with ahead/behind counts. A merge, rebase, cherry-pick or revert
that stops on conflicts shows a banner with **Continue**, **Skip** and **Abort**: resolve the files in
Conflicts, save, and press Continue, without a terminal.

Everything runs through your own `git`, so your credentials, hooks and signing work as in a terminal.

`lfgit open` (in a repository) or **File › Open Repository…** shows every conflicted file; pick one
and resolve it the way VS Code does, but on files of any size.

- Each conflict has **Accept Current · Accept Incoming · Accept Both · Accept Base · Compare**; a
  resolved conflict stays visible with the discarded side struck through, and **Undo** is one click away.
- The conflict map on the right shows where conflicts are and which are resolved; click to jump.
- **Re-merge Project** merges `project.pbxproj` object by object; binary files offer *Use Current* /
  *Use Incoming* with image previews.
- Saving writes the file (open conflicts keep their markers) and, once everything is resolved, stages it.
- Light and dark mode follow the system, or choose in Settings (⌘,).

| Shortcut | Action |
|---|---|
| ⌥⌘↓ / ⌥⌘↑ | Next / previous conflict (unresolved first) |
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | Accept current / incoming / both / base |
| ⇧⌘1 / ⇧⌘2 | Accept all current / all incoming |
| ⌘Z / ⇧⌘Z | Undo / redo a resolution |
| ⌘S | Save (and stage when fully resolved) |
| ⌘R | Reload (also reloads the diff on screen) |
| ⌥⌘F / ⌥⌘L / ⌥⌘P | Fetch / pull / push |
| ⌘↩ | Commit |

A 2,000,000-line file with 1,000 conflicts opens in about 2.6 s from launch; rows are read from the
engine only when they scroll into view.

## Command line

```bash
lfgit status                          # conflicted files: type, number of conflicts, size
lfgit resolve --all-current  a.txt    # also: --all-incoming, --all-both, --all-both-incoming-first, --all-base
lfgit resolve --all-incoming --stage  # no file arguments = every conflicted file; --stage runs git add
lfgit tui path/to/file                # interactive: [c]urrent [i]ncoming [b]oth [B]oth-reversed [a]ncestor [e]dit [k]eep [q]uit
lfgit install                         # register as `git mergetool` + merge driver (this repo; --global for all)
git mergetool                         # now opens lfgit's interactive resolver for each conflicted file
lfgit open [file]                     # open this repository (and file) in the app
lfgit install --attributes '*.pbxproj'   # merge project files object by object during every merge
lfgit remerge [--stage]               # already conflicted? re-merge project.pbxproj from git's index (old file kept as .orig)
```

- Binary files can take a whole side (`--all-current` / `--all-incoming`).
- `-C <dir>` works like in git. `NO_COLOR` disables colours.
- Base sections (`--all-base`, `a` in `tui`) need `git config merge.conflictStyle diff3`; the merge driver always writes diff3 markers.

### Xcode project files

`project.pbxproj` is merged **object by object** instead of line by line: an object changed on one
side takes that side's text, objects changed on both sides are merged field by field (build
settings key by key, file lists as ordered sets). Only real disagreements remain, as small conflict
blocks around one setting or one object, which `lfgit tui` / `resolve` can finish. Safety rules: flag
lists inside `buildSettings` are never merged as sets, a deletion the other side still uses becomes a
conflict, and files that are not in Xcode's format fall back to git's line merge.

Replayed on real merge commits of three open-source iOS apps (`LFCore/Scripts/pbxproj_corpus.py`):

| Repository | Both sides changed the project | git conflicted | lfgit resolved those |
|---|---|---|---|
| wikimedia/wikipedia-ios | 96 | 22 | 22 |
| wordpress-mobile/WordPress-iOS | 93 | 8 | 8 |
| kickstarter/ios-oss | 29 | 15 | 14 (1 broken input left to git) |

No result disagreed with the committed project in a way lfgit could have known. Known limits: a file
kept by resolving a modify/delete conflict loses its project entry (`lfgit remerge` warns), and two
differently named files that contain the same code are both kept.

### Performance

`swift run -c release lf-bench` generates a conflicted file and measures it. On an Apple-silicon Mac:

| File | Open + index + scan (warm) |
|---|---|
| 10 million lines (305 MB), 10,000 conflicts | 0.07 s |
| 100 million lines (3.1 GB), 100,000 conflicts | 0.8 s |

Files are memory-mapped and indexed sparsely (one offset per 1024 lines), so memory use stays small.

### Theme

Colors are defined once in `Design/theme.json`. After editing it, regenerate the asset catalog color sets:

```bash
python3 LFCore/Scripts/gen_theme.py          # regenerate + check WCAG AA contrast
python3 LFCore/Scripts/gen_theme.py --check  # CI: fail on drift or low contrast
```

### Test data

```bash
python3 LFCore/Scripts/gen_conflicts.py --lines 1000000 --conflicts 1000 --kind pbxproj --out big.generated.pbxproj
```

## Install

Homebrew (build from source) is planned: `brew install alifu/tap/lfgit`.

## License

MIT, see [LICENSE](LICENSE).
