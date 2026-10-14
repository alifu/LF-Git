#!/bin/bash
# Copies the screenshots taken by ScreenshotTourUITests into docs/images/.
#
#   xcodebuild test -scheme LF-Git -destination 'platform=macOS' -only-testing:LF-GitUITests/ScreenshotTourUITests
#   Scripts/docs/export-screenshots.sh [path/to/Test-….xcresult]     (default: the newest result in DerivedData)
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

mkdir -p "$root/docs/images"
python3 - "$work" "$root/docs/images" <<'PY'
import json, re, shutil, sys
from pathlib import Path

work, out = Path(sys.argv[1]), Path(sys.argv[2])
copied = 0
for test in json.loads((work / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        match = re.match(r"shot-([a-z0-9-]+?)(?:_\d+_[0-9A-Fa-f-]+)?(?:\.\w+)?$", attachment["suggestedHumanReadableName"])
        if not match:
            continue
        shutil.copy(work / attachment["exportedFileName"], out / f"{match.group(1)}.png")
        copied += 1
        print(f"docs/images/{match.group(1)}.png")
if not copied:
    sys.exit("no shot-* attachments in that result")
PY
