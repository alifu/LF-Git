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

The window has ten sections, reachable from the grid at the top of the sidebar, with **⌃1 … ⌃0**, or from the
command palette (**⌘K**): **Changes · Branches · History · Stash · Tags · Remotes · Reflog · Worktrees ·
Submodules · Conflicts**. Everything runs through your own `git`, so credentials, hooks and signing work as in a
terminal, and every command is listed in the **command log** (⇧⌘L).

| Section | What you can do |
|---|---|
| **Changes** | Stage/unstage files, **hunks** or **single lines** (select lines in the diff), discard (lines too), commit, amend, skip hooks, ignore a file (`.gitignore` or local exclude), stash one file, file history. Diff options: ignore whitespace, context size, rename detection |
| **Branches** | Checkout, new, rename, delete (local and on the remote), merge (default / no-ff / ff-only / squash), rebase onto, reset (soft/mixed/hard), fast-forward from upstream, set/unset upstream, compare with the current branch |
| **History** | Graph, filter by message/author/file, **reword, edit, squash, fixup, drop, move up/down**, amend an older commit with staged changes, fixup commits and autosquash, revert, **cherry-pick** (copy commits, paste on another branch), reset, detached checkout, branch/tag from a commit, **bisect**, compare any two commits, **blame**, file history. Select lines of a commit's diff to apply them, revert them, or cut them out of the commit |
| **Stash** | Stash all / with untracked / staged only / keep index, apply, pop, drop, rename, branch from stash, browse its diff |
| **Tags** | Lightweight and annotated tags, push, delete (local and remote), checkout, branch from tag |
| **Remotes** | Add, rename, change URL, remove, fetch, prune, browse remote branches |
| **Reflog** | Browse, checkout, reset, cherry-pick, branch; **Undo** the last HEAD move (the same button redoes it) |
| **Worktrees / Submodules** | Add, remove, open; add, update, remove submodules |

**Toolbar:** branch menu, **Fetch**, **Pull** (fast-forward only, merge or rebase), **Push** (and **force push with
lease**) with ahead/behind counts. Fetch, pull, push and other network commands show a **Cancel** button and stop
by themselves after 5 minutes; git never prompts for a password. A merge, rebase, cherry-pick or revert that stops
on conflicts shows a banner with **Continue**, **Skip** and **Abort**: resolve the files in Conflicts, save, and
press Continue, without a terminal.

The window follows edits made in an editor or terminal (file-system events), and **File › Open Recent** lists the
repositories you used.

**Custom commands:** put your own shell commands in `~/.config/lfgit/config.json`; they appear in the command
palette and run in the repository (`$LFGIT_REPO`, `$LFGIT_BRANCH` are set):

```json
{ "customCommands": [ { "name": "Prune merged branches", "command": "git branch --merged | grep -v '\\*' | xargs git branch -d" } ] }
```

Rewriting history works on the checked-out branch and refuses ranges that contain merge commits; your local edits
are stashed and restored around it.

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
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | Accept current / incoming / both / base (in Conflicts) |
| ⇧⌘1 / ⇧⌘2 | Accept all current / all incoming |
| ⌘Z / ⇧⌘Z | Undo / redo a resolution |
| ⌘S | Save (and stage when fully resolved) |
| ⌘R | Reload (also reloads the diff on screen) |
| ⌥⌘F / ⌥⌘L / ⌥⌘P | Fetch / pull / push |
| ⌘↩ | Commit |
| ⌘K / ⇧⌘L / ⌘/ | Command palette / command log / shortcut list |
| ⌃1 … ⌃0 | Go to a section |
| ⌥⌘Z | Undo the last git move (reflog) |

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
