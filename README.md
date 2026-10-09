# LF-Git

A native macOS merge tool and Git client for resolving conflicts in **files of any size**, from a Swift source file to an Xcode `project.pbxproj` with millions of lines.

> **Status:** early development. The C engine and the `lfgit` command line tool work (phases 1 and 2); the SwiftUI conflict editor and the semantic `.pbxproj` merge are next.

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

## Command line

```bash
lfgit status                          # conflicted files: type, number of conflicts, size
lfgit resolve --all-current  a.txt    # also: --all-incoming, --all-both, --all-both-incoming-first, --all-base
lfgit resolve --all-incoming --stage  # no file arguments = every conflicted file; --stage runs git add
lfgit tui path/to/file                # interactive: [c]urrent [i]ncoming [b]oth [B]oth-reversed [a]ncestor [e]dit [k]eep [q]uit
lfgit install                         # register as `git mergetool` + merge driver (this repo; --global for all)
git mergetool                         # now opens lfgit's interactive resolver for each conflicted file
lfgit install --attributes '*.pbxproj'   # route these files through the lfgit merge driver
```

- Binary files can take a whole side (`--all-current` / `--all-incoming`).
- `-C <dir>` works like in git. `NO_COLOR` disables colours.
- Base sections (`--all-base`, `a` in `tui`) need `git config merge.conflictStyle diff3`; the merge driver always writes diff3 markers.

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
