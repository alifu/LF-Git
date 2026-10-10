#!/bin/sh
# Fails unless the app, the command line tool and the formula all name the same version.
#
#   Scripts/release/check-version.sh [expected-version]
set -eu

app="$(sed -n 's/.*MARKETING_VERSION = \([0-9][0-9.]*\);/\1/p' LF-Git.xcodeproj/project.pbxproj | sort -u | grep -v '^1\.0$' | head -n 1)"
major="$(sed -n 's/#define LF_VERSION_MAJOR \([0-9]*\)/\1/p' LFCore/Sources/LFCore/include/lfcore.h)"
minor="$(sed -n 's/#define LF_VERSION_MINOR \([0-9]*\)/\1/p' LFCore/Sources/LFCore/include/lfcore.h)"
patch="$(sed -n 's/#define LF_VERSION_PATCH \([0-9]*\)/\1/p' LFCore/Sources/LFCore/include/lfcore.h)"
tool="${major}.${minor}.${patch}"
formula="$(sed -n 's|.*refs/tags/v\([0-9][0-9.]*\)\.tar\.gz.*|\1|p' Formula/lfgit.rb | head -n 1)"
expected="${1:-$app}"

echo "app $app, lfgit $tool, formula $formula, expected $expected"
[ "$app" = "$expected" ] && [ "$tool" = "$expected" ] && [ "$formula" = "$expected" ] || {
  echo "version mismatch" >&2
  exit 1
}
