#!/bin/sh
# Builds the source archive that the Homebrew formula downloads, and prints its SHA-256.
#
#   Scripts/release/make-source-archive.sh [ref] [output-dir]
#
# The archive is exactly what GitHub serves for a tag (`git archive` with the same prefix), so the
# checksum matches what `brew` will compute. Use it to try the formula before a release exists.
set -eu

ref="${1:-HEAD}"
out="${2:-$(pwd)/dist}"
version="$(sed -n 's/.*MARKETING_VERSION = \([0-9][0-9.]*\);/\1/p' LF-Git.xcodeproj/project.pbxproj | head -n 1)"
name="LF-Git-${version}"

mkdir -p "$out"
git archive --format=tar.gz --prefix="${name}/" -o "${out}/${name}.tar.gz" "$ref"
sum="$(shasum -a 256 "${out}/${name}.tar.gz" | cut -d ' ' -f 1)"
echo "archive: ${out}/${name}.tar.gz"
echo "sha256:  ${sum}"
