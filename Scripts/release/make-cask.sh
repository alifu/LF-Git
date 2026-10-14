#!/bin/sh
# Prints the Homebrew cask of a release, which installs the prebuilt LF-Git.app and the lfgit tool.
#
#   Scripts/release/make-cask.sh VERSION SHA256 > lf-git.rb
#
# The Release workflow runs this and attaches the result to the GitHub release; copy it to Casks/lf-git.rb in
# alifu/homebrew-tap (the workflow does that itself when the TAP_TOKEN secret is set).
set -eu

[ $# -eq 2 ] || { echo "usage: make-cask.sh VERSION SHA256" >&2; exit 2; }
version="$1"
sha="$2"
case "$version" in *[!0-9.]* | "") echo "bad version: $version" >&2; exit 2 ;; esac
case "$sha" in *[!0-9a-f]* | "") echo "bad sha256: $sha" >&2; exit 2 ;; esac
[ "${#sha}" -eq 64 ] || { echo "sha256 must be 64 hex digits" >&2; exit 2; }

cat <<RUBY
cask "lf-git" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/alifu/LF-Git/releases/download/v#{version}/LF-Git.zip"
  name "LF-Git"
  desc "Merge tool and Git client for conflicts in files of any size"
  homepage "https://github.com/alifu/LF-Git"

  depends_on macos: ">= :sonoma"

  app "LF-Git.app"
  binary "lfgit"

  uninstall quit: "com.alifu.LF-Git"

  zap trash: [
    "~/.config/lfgit",
    "~/Library/Preferences/com.alifu.LF-Git.plist",
    "~/Library/Saved Application State/com.alifu.LF-Git.savedState",
  ]
end
RUBY
