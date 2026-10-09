#!/usr/bin/env python3
"""Replay real project.pbxproj merges from a git repository and score lfgit's semantic merge.

For every merge commit M (two parents P1, P2) where both parents changed the same *.pbxproj
relative to their merge base B, the script:
  1. runs git's own line-based merge (git merge-file) on B/P1/P2,
  2. runs `lfgit driver` (object-level merge) on the same three files,
  3. compares every clean lfgit result with M, the version the developers committed.

A clean result that differs from M is classified object by object, using M's file tree:
  - "human edit": M changed the object in a way neither parent had (a fix-up made during the
    merge), so no merge tool could have produced it;
  - "developer error": M's project disagrees with M's own tree (it lists files that are gone,
    or lost files that are there) while lfgit's result matches the tree;
  - "coupled": lfgit dropped a file that is still in M's tree, i.e. a deletion that the developer
    undid by resolving a modify/delete conflict on the file itself (`lfgit remerge` warns);
  - "inherited": lfgit kept a reference that was already dangling in ours or theirs;
  - "suspect": lfgit lists a file that is not in the tree, or any other difference.
Suspects are printed for manual review; the gate is zero.

Usage:
  pbxproj_corpus.py --repo PATH --lfgit PATH/TO/lfgit [--limit 2000] [--show 5]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

FILE_NAME = re.compile(rb"/\* ([^*]+?)(?: in [A-Za-z ]+)? \*/")
ENTRY_START = re.compile(rb"^\t\t(\S+) (?:/\*.*?\*/ )?= \{")
SECTION_BEGIN = re.compile(rb"^/\* Begin (\S+) section \*/$")


def git(repo: Path, *args: str, check: bool = True) -> bytes:
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def objects_of(text: bytes) -> dict[bytes, bytes] | None:
    """Object ID -> raw entry text, for Xcode-formatted files; None if the layout is unexpected."""
    objects: dict[bytes, bytes] = {}
    current_id: bytes | None = None
    current: list[bytes] = []
    in_section = False
    for line in text.split(b"\n"):
        if SECTION_BEGIN.match(line):
            in_section = True
            continue
        if line.startswith(b"/* End "):
            in_section = False
            continue
        if not in_section:
            continue
        if current_id is None:
            match = ENTRY_START.match(line)
            if not match:
                return None
            current_id, current = match.group(1), [line]
            if line.endswith(b"};"):
                objects[current_id] = line
                current_id = None
            continue
        current.append(line)
        if line == b"\t\t};":
            objects[current_id] = b"\n".join(current)
            current_id = None
    return objects if current_id is None else None


@dataclass
class Case:
    merge: str
    path: str
    git_conflicts: bool = False
    outcome: str = ""  # clean / conflicts / fallback / error
    verdict: str = ""  # exact / equivalent / human-edit / suspect
    details: list[str] = field(default_factory=list)


COMMENT = re.compile(rb"\s*/\*.*?\*/")


def normalized(text: bytes | None) -> bytes | None:
    """Object text without comments or quotes: formatting changes between Xcode versions compare equal."""
    if text is None:
        return None
    return b" ".join(COMMENT.sub(b"", text).replace(b'"', b"").split())


def file_names(text: bytes | None) -> set[bytes]:
    return {name for name in FILE_NAME.findall(text or b"") if b"." in name}


def dangling_in_input(name: bytes, mine: bytes, inputs: list[dict[bytes, bytes]], raw_inputs: list[bytes]) -> bool:
    """Is every line of `mine` that names `name` copied from an input where the referenced ID was undefined?"""
    for line in mine.split(b"\n"):
        if b"/* " + name + b" */" not in line:
            continue
        referenced = line.strip().split(b" ")[0]
        if not any(line in raw and referenced not in objs for raw, objs in zip(raw_inputs, inputs)):
            return False
    return True


def tree_verdict(mine: bytes | None, committed: bytes | None, tree: set[bytes],
                 inputs: list[dict[bytes, bytes]], raw_inputs: list[bytes]) -> str:
    extra = file_names(mine) - file_names(committed)
    missing = file_names(committed) - file_names(mine)
    if not extra and not missing:
        return "suspect"
    absent = [name for name in extra if name not in tree]
    if absent and all(dangling_in_input(name, mine or b"", inputs, raw_inputs) for name in absent):
        return "inherited"
    if absent:
        return "suspect"  # lfgit lists a file the merged tree does not have
    if any(name in tree for name in missing):
        return "coupled"
    return "developer-error"


def classify(result: bytes, truth: bytes, base: bytes, ours: bytes, theirs: bytes, case: Case,
             tree: set[bytes] | None = None) -> None:
    if result == truth:
        case.verdict = "exact"
        return
    parsed = [objects_of(x) for x in (result, truth, base, ours, theirs)]
    if any(p is None for p in parsed):
        case.verdict = "suspect"
        case.details.append("could not split objects for comparison")
        return
    r, m, b, o, t = parsed  # type: ignore[misc]
    human, orphans, suspect, developer, coupled = [], [], [], [], []
    for object_id in sorted(set(r) | set(m)):
        mine, committed = r.get(object_id), m.get(object_id)
        if mine == committed or normalized(mine) == normalized(committed):
            continue
        sides = {b.get(object_id), o.get(object_id), t.get(object_id)}
        if committed not in sides:
            human.append(object_id.decode())  # the committed version exists in no input: a manual fix-up
        elif mine is None and truth.count(object_id) == 1:
            orphans.append(object_id.decode())  # kept by the developer but referenced by nothing
        else:
            verdict = tree_verdict(mine, committed, tree or set(), [o, t], [ours, theirs])
            names = sorted(n.decode() for n in file_names(mine) ^ file_names(committed))[:2]
            note = f"{object_id.decode()}: {verdict} ({', '.join(names) or 'no file names'})"
            {"developer-error": developer, "coupled": coupled, "inherited": developer}.get(verdict, suspect).append(note)
    if suspect:
        case.verdict = "suspect"
        case.details.extend(suspect[:6])
    elif coupled:
        case.verdict = "coupled"
        case.details.extend(coupled[:4])
    elif developer:
        case.verdict = "developer-error"
        case.details.extend(developer[:4])
    elif orphans:
        case.verdict = "human-orphans"
        case.details.extend(f"object {x} kept unused by the developer" for x in orphans[:5])
    elif human:
        case.verdict = "human-edit"
        case.details.extend(f"object {h} was edited by hand during the merge" for h in human[:5])
    else:
        case.verdict = "equivalent"  # same objects, different order or header text


def replay(repo: Path, lfgit: str, merge: str, base: str, p1: str, p2: str, path: str, scratch: Path,
           dump: Path | None = None) -> Case:
    case = Case(merge=merge, path=path)
    blobs = {}
    for name, rev in (("O", base), ("A", p1), ("B", p2), ("M", merge)):
        blobs[name] = git(repo, "show", f"{rev}:{path}", check=False)
    for name in ("O", "A", "B"):
        (scratch / name).write_bytes(blobs[name])
    text_merge = subprocess.run(
        ["git", "merge-file", "-p", "--diff3", str(scratch / "A"), str(scratch / "O"), str(scratch / "B")],
        capture_output=True,
    )
    case.git_conflicts = text_merge.returncode != 0
    driver = subprocess.run(
        [lfgit, "driver", str(scratch / "O"), str(scratch / "A"), str(scratch / "B"), "7", path], capture_output=True
    )
    stderr = driver.stderr.decode(errors="replace")
    if "line-based merge" in stderr:
        case.outcome = "fallback"
        case.details.append(stderr.strip().splitlines()[0] if stderr.strip() else "fallback")
        return case
    if driver.returncode not in (0, 1):
        case.outcome = "error"
        case.details.append(stderr.strip())
        return case
    merged = (scratch / "A").read_bytes()
    case.outcome = "clean" if driver.returncode == 0 else "conflicts"
    if dump is not None and case.outcome == "conflicts":
        target = dump / f"{merge[:10]}-{path.replace('/', '_')}"
        target.mkdir(parents=True, exist_ok=True)
        for name in ("O", "A", "B", "M"):
            (target / name).write_bytes(blobs[name])
        (target / "result").write_bytes(merged)
    if case.outcome == "clean":
        tree = {Path(p).name.encode() for p in git(repo, "ls-tree", "-r", "--name-only", merge).decode().split("\n") if p}
        classify(merged, blobs["M"], blobs["O"], blobs["A"], blobs["B"], case, tree)
    return case


def candidate_merges(repo: Path, limit: int) -> list[tuple[str, str, str]]:
    lines = git(repo, "rev-list", "--merges", "--parents", f"--max-count={limit}", "HEAD").decode().split("\n")
    merges = []
    for line in lines:
        parts = line.split()
        if len(parts) == 3:
            merges.append((parts[0], parts[1], parts[2]))
    return merges


def changed_projects(repo: Path, base: str, rev: str) -> set[str]:
    out = git(repo, "diff", "--name-only", base, rev, "--", "*.pbxproj").decode()
    return {p for p in out.split("\n") if p}


PREFETCH_BATCH = 200


def prefetch(repo: Path, specs: list[str]) -> None:
    """Downloads the needed blobs of a partial clone in batches instead of one request per blob."""
    if not specs:
        return
    oids = [o for o in git(repo, "rev-parse", *specs, check=False).decode().split() if len(o) == 40]
    probe = subprocess.run(
        ["git", "-C", str(repo), "cat-file", "--batch-check"], input="\n".join(oids).encode(), capture_output=True,
        env={**__import__("os").environ, "GIT_NO_LAZY_FETCH": "1"},
    )
    missing = [line.split()[0] for line in probe.stdout.decode().split("\n") if line.endswith(" missing")]
    for start in range(0, len(missing), PREFETCH_BATCH):
        subprocess.run(
            ["git", "-C", str(repo), "-c", "fetch.negotiationAlgorithm=noop", "fetch", "-q", "--no-tags",
             "--no-write-fetch-head", "--recurse-submodules=no", "--filter=blob:none", "origin",
             *missing[start:start + PREFETCH_BATCH]],
            capture_output=True,
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--lfgit", required=True)
    parser.add_argument("--limit", type=int, default=2000, help="merge commits to inspect")
    parser.add_argument("--show", type=int, default=5, help="details to print per category")
    parser.add_argument("--dump", type=Path, help="save base/ours/theirs/committed/result of cases with conflicts here")
    args = parser.parse_args()

    planned: list[tuple[str, str, str, str, str]] = []
    for merge, p1, p2 in candidate_merges(args.repo, args.limit):
        base = git(args.repo, "merge-base", p1, p2, check=False).decode().strip()
        if not base:
            continue
        both = changed_projects(args.repo, base, p1) & changed_projects(args.repo, base, p2)
        for path in sorted(both):
            if git(args.repo, "rev-parse", f"{p1}:{path}", check=False) != git(args.repo, "rev-parse", f"{p2}:{path}", check=False):
                planned.append((merge, base, p1, p2, path))
    print(f"replaying {len(planned)} project-file merges...", file=sys.stderr)
    prefetch(args.repo, [f"{rev}:{path}" for merge, base, p1, p2, path in planned for rev in (base, p1, p2, merge)])

    cases: list[Case] = []
    with tempfile.TemporaryDirectory() as directory:
        scratch = Path(directory)
        for merge, base, p1, p2, path in planned:
            cases.append(replay(args.repo, args.lfgit, merge, base, p1, p2, path, scratch, args.dump))

    conflicted = [c for c in cases if c.git_conflicts]
    print(f"repository: {args.repo}")
    print(f"merges where both sides changed a project file: {len(cases)}")
    print(f"  git's line merge conflicted: {len(conflicted)}")
    for label, subset in (("all cases", cases), ("cases git could not merge", conflicted)):
        outcomes = Counter(c.outcome for c in subset)
        verdicts = Counter(c.verdict for c in subset if c.outcome == "clean")
        clean = outcomes.get("clean", 0)
        rate = 100.0 * clean / len(subset) if subset else 0.0
        print(f"\n{label}: {len(subset)}")
        print(f"  lfgit outcome: {dict(outcomes)}  (auto-resolved {rate:.1f}%)")
        print(f"  clean results vs committed: {dict(verdicts)}")
    for category in ("suspect", "coupled", "developer-error", "fallback", "error"):
        selected = [c for c in cases if c.verdict == category or c.outcome == category]
        for c in selected[: args.show]:
            print(f"\n[{category}] {c.merge[:10]} {c.path}")
            for line in c.details:
                print(f"    {line}")
    suspects = sum(1 for c in cases if c.verdict == "suspect")
    print(f"\nsuspect merges (gate: 0): {suspects}")
    return 1 if suspects else 0


if __name__ == "__main__":
    sys.exit(main())
