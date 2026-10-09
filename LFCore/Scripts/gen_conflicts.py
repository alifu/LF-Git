#!/usr/bin/env python3
"""Generate a synthetic conflicted file for tests and benchmarks.

Examples:
  gen_conflicts.py --lines 10000000 --conflicts 10000 --out big.generated.pbxproj --kind pbxproj
  gen_conflicts.py --lines 5000 --conflicts 20 --style diff3 --eol crlf --out sample.swift

Output is streamed, so memory stays flat regardless of --lines.
"""

from __future__ import annotations

import argparse
import random
import sys
from collections.abc import Iterator
from pathlib import Path

MARKER_SIZE = 7
CONFLICT_SIDE_LINES = 3
SEED = 1337


def uuid24(rng: random.Random) -> str:
    return "".join(rng.choice("0123456789ABCDEF") for _ in range(24))


def text_line(index: int, rng: random.Random, side: str = "") -> str:
    return f"    let value{index}{side} = compute({rng.randint(0, 99999)})  // line {index}"


def pbxproj_line(index: int, rng: random.Random, side: str = "") -> str:
    name = f"File{index}{side}.swift"
    return (
        f"\t\t{uuid24(rng)} /* {name} */ = {{isa = PBXFileReference; "
        f'lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }};'
    )


def conflict_block(index: int, rng: random.Random, make_line, style: str) -> Iterator[str]:
    yield "<" * MARKER_SIZE + " HEAD"
    for offset in range(CONFLICT_SIDE_LINES):
        yield make_line(index + offset, rng, "Ours")
    if style == "diff3":
        yield "|" * MARKER_SIZE + " merged common ancestors"
        for offset in range(CONFLICT_SIDE_LINES):
            yield make_line(index + offset, rng, "Base")
    yield "=" * MARKER_SIZE
    for offset in range(CONFLICT_SIDE_LINES):
        yield make_line(index + offset, rng, "Theirs")
    yield ">" * MARKER_SIZE + " feature/incoming"


def generate(lines: int, conflicts: int, kind: str, style: str) -> Iterator[str]:
    rng = random.Random(SEED)
    make_line = pbxproj_line if kind == "pbxproj" else text_line
    interval = max(1, lines // (conflicts + 1)) if conflicts else lines + 1
    emitted_conflicts = 0
    for index in range(lines):
        if conflicts and index % interval == 0 and emitted_conflicts < conflicts:
            yield from conflict_block(index, rng, make_line, style)
            emitted_conflicts += 1
        yield make_line(index, rng)


def positive_int(value: str) -> int:
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("must be >= 0")
    return number


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lines", type=positive_int, required=True, help="regular (non-conflict) lines")
    parser.add_argument("--conflicts", type=positive_int, default=0, help="number of conflict blocks")
    parser.add_argument("--kind", choices=("text", "pbxproj"), default="text")
    parser.add_argument("--style", choices=("merge", "diff3"), default="merge")
    parser.add_argument("--eol", choices=("lf", "crlf"), default="lf")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    if args.conflicts > args.lines:
        print("error: --conflicts cannot exceed --lines", file=sys.stderr)
        return 1

    eol = "\r\n" if args.eol == "crlf" else "\n"
    try:
        with args.out.open("w", encoding="utf-8", newline="") as handle:
            for line in generate(args.lines, args.conflicts, args.kind, args.style):
                handle.write(line + eol)
    except OSError as error:
        print(f"error: cannot write {args.out}: {error}", file=sys.stderr)
        return 1
    print(f"wrote {args.out} ({args.lines} lines, {args.conflicts} conflicts, {args.kind}, {args.style}, {args.eol})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
