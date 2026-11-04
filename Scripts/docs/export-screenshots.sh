#!/bin/bash
# Copies the screenshots taken by ScreenshotTourUITests into docs/images/.
#
#   xcodebuild test -scheme LF-Git -destination 'platform=macOS' -only-testing:LF-GitUITests/ScreenshotTourUITests
#   Scripts/docs/export-screenshots.sh [path/to/Test-….xcresult]     (default: the newest result in DerivedData)
#
# The layout tour (LayoutTourUITests) names its attachments `layout-…`; pick them and another folder with:
#   PREFIX=layout OUT=.claude/plans/gitbutler-layouts/screens Scripts/docs/export-screenshots.sh [result]
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
result="${1:-}"
if [ -z "$result" ]; then
    result="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/LF-Git-*/Logs/Test/*.xcresult 2>/dev/null | head -1)"
fi
[ -n "$result" ] || { echo "no .xcresult found; run the screenshot tour first" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
xcrun xcresulttool export attachments --path "$result" --output-path "$work" >/dev/null

prefix="${PREFIX:-shot}"
out="${OUT:-docs/images}"
case "$out" in /*) ;; *) out="$root/$out" ;; esac
mkdir -p "$out"
python3 - "$work" "$out" "$prefix" <<'PY'
import json, re, shutil, sys
from pathlib import Path

work, out, prefix = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
copied = 0
for test in json.loads((work / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        match = re.match(re.escape(prefix) + r"-([A-Za-z0-9-]+?)(?:_\d+_[0-9A-Fa-f-]+)?(?:\.\w+)?$", attachment["suggestedHumanReadableName"])
        if not match:
            continue
        shutil.copy(work / attachment["exportedFileName"], out / f"{match.group(1)}.png")
        copied += 1
        print(out / f"{match.group(1)}.png")
if not copied:
    sys.exit(f"no {prefix}-* attachments in that result")
PY
