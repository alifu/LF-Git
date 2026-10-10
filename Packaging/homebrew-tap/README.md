# What goes into `alifu/homebrew-tap`

The tap already exists (`lf-capcheck`). To publish LF-Git, copy into it:

| From this folder / repo | To the tap |
|---|---|
| `Formula/lfgit.rb` (with the real `sha256`) | `Formula/lfgit.rb` |
| `Packaging/homebrew-tap/.github/workflows/lfgit.yml` | `.github/workflows/lfgit.yml` |

Then users run `brew install alifu/tap/lfgit`.

Per release: tag `vX.Y.Z` in LF-Git → the Release workflow prints the formula's `url` and `sha256` in the
release notes → update them in the tap formula → push. See `RELEASING.md` in the LF-Git repository.
