# Releasing LF-Git

LF-Git is not notarized (no Apple Developer account), so the main channel is a Homebrew formula that **builds from
source** on the user's Mac: software compiled locally is never quarantined, so Gatekeeper has nothing to block.

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
4. The **Release** workflow checks the versions, tests, builds the app and `lfgit`, and publishes a GitHub Release with
   the prebuilt zip and the formula's `url` and `sha256` in the notes.
5. In the tap (`alifu/homebrew-tap`) put those two values into `Formula/lfgit.rb` and push. The tap's workflow builds
   the formula from source, runs `brew test` and `brew audit`.
6. Check: `brew update && brew install alifu/tap/lfgit && lfgit --version`.

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
- `lfgit open` finds `LF-Git.app` next to `bin/` in the keg; `brew` prints how to link it into `/Applications`.
- The prebuilt zip is best effort: it is ad-hoc signed, and the user must run `xattr -dr com.apple.quarantine` once.
- If you later get a Developer ID: add Hardened Runtime and notarization to the Release workflow and publish a cask.
