# Releasing LF-Git

LF-Git is not notarized (no Apple Developer account). The main channel is a **prebuilt app**: a Homebrew cask
(`brew install --cask alifu/tap/lf-git`) and `LF-Git.zip` on the GitHub release, so nobody needs Xcode to install it.
A formula that **builds from source** (`brew install alifu/tap/lfgit`) stays for contributors; software compiled
locally is never quarantined. Users of the prebuilt app allow it once under *Privacy & Security › Open Anyway* (see the
README's Install section).

## One release

1. Pick the version `X.Y.Z`. Set it in all three places and check them:
   - `MARKETING_VERSION` in `LF-Git.xcodeproj` (the app),
   - `LF_VERSION_MAJOR/MINOR/PATCH` in `LFCore/Sources/LFCore/include/lfcore.h` (`lfgit --version`),
   - the tag in `Formula/lfgit.rb`'s `url` (`.../refs/tags/vX.Y.Z.tar.gz`).

   ```sh
   sh Scripts/release/check-version.sh
   ```
2. Run the checks: `swift test --package-path LFCore`, `xcodebuild … test`, and a Release build
   (`xcodebuild -project LF-Git.xcodeproj -scheme LF-Git -configuration Release CODE_SIGN_IDENTITY=- build`,
   which can fail where Debug does not).
3. Commit, then tag and push: `git tag vX.Y.Z && git push origin main vX.Y.Z`.
4. The **Release** workflow checks the versions, tests, builds the universal app and `lfgit`, and publishes a GitHub
   Release with `LF-Git.zip` (the app, `lfgit`, the license), `LF-Git.zip.sha256`, and `lf-git.rb` (the finished cask).
   The notes also show the source formula's `url` and `sha256`.
5. **The cask** goes to the tap as `Casks/lf-git.rb`:
   - automatic: add a repository secret `TAP_TOKEN` (a token that can push to `alifu/homebrew-tap`) and the workflow
     commits the cask itself;
   - manual: copy the release's `lf-git.rb` to `Casks/lf-git.rb` in the tap and push.

   The **formula** (source build): put the `url` and `sha256` from the notes into `Formula/lfgit.rb` in this
   repository and in the tap. The tap's workflow builds it from source, runs `brew test` and `brew audit`.
6. Check on a Mac without Xcode if you can: `brew update && brew install --cask alifu/tap/lf-git && lfgit --version`,
   and open the app (allow it once).

## What the cask installs

`Scripts/release/make-cask.sh VERSION SHA256` renders the cask. It installs `LF-Git.app` into `/Applications` and links
`lfgit` into Homebrew's `bin/`. `lfgit open` finds the app by name through macOS when it is not next to the binary.

## Try the formula before a tag exists

```sh
sh Scripts/release/make-source-archive.sh HEAD /tmp/lfgit-dist     # prints the archive path and sha256
brew tap-new --no-git local/lfgit-test
# copy Formula/lfgit.rb into $(brew --repository local/lfgit-test)/Formula/ and change url to file:///tmp/lfgit-dist/LF-Git-X.Y.Z.tar.gz
brew install --build-from-source local/lfgit-test/lfgit && brew test local/lfgit-test/lfgit
```

## Notes

- The formula requires Xcode 26 or later (`depends_on xcode: ["26.0", :build]`). The command line tool alone builds with
  `swift build --package-path LFCore -c release --product lfgit` and needs only a Swift toolchain.
- Inside Homebrew's build sandbox `xcodebuild` cannot nest a second sandbox, so the formula passes
  `-IDEPackageSupportDisableManifestSandbox=1` and `OTHER_SWIFT_FLAGS=-disable-sandbox` (needed for SwiftPM and for the
  `@Observable` / `#Preview` macros).
- `lfgit open` finds `LF-Git.app` next to `bin/` in the keg (formula), or by name (cask).
- The zip is universal (arm64 + x86_64) and ad-hoc signed.
- If you later get a Developer ID: add Hardened Runtime and notarization to the Release workflow; the "Open Anyway" step
  disappears.
