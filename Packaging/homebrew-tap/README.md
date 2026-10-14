# What goes into `alifu/homebrew-tap`

The tap already exists (`lf-paper`, `lf-capcheck`, …). LF-Git publishes two things there:

| What | From | To the tap | Install command |
|---|---|---|---|
| **Cask** (the prebuilt app and `lfgit`; the main channel) | `lf-git.rb`, attached to every GitHub release (made by `Scripts/release/make-cask.sh`) | `Casks/lf-git.rb` | `brew install --cask alifu/tap/lf-git` |
| **Formula** (builds from source; for contributors) | `Formula/lfgit.rb` with the real `sha256` | `Formula/lfgit.rb` | `brew install alifu/tap/lfgit` |

Also copy `Packaging/homebrew-tap/.github/workflows/lfgit.yml` to `.github/workflows/lfgit.yml` in the tap: it builds
the formula, audits it, and audits the cask.

Per release: tag `vX.Y.Z` in LF-Git → the Release workflow publishes `LF-Git.zip` and `lf-git.rb`. With a `TAP_TOKEN`
secret the workflow updates the tap's cask itself; otherwise copy `lf-git.rb` over by hand. The formula's `url` and
`sha256` are in the release notes. See `RELEASING.md` in the LF-Git repository.
