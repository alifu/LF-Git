# Hooks panel

Hooks that a push or commit runs print into a panel inside LF-Git instead of leaving that to terminal windows.

* **Panel**: opens above the Log panel when a push or commit starts and the repository has a matching hook
  (`pre-push`; `pre-commit`, `prepare-commit-msg`, `commit-msg`, `post-commit`). It shows live output, a status chip
  (running / passed / failed with time), Copy, Clear and a picker for the last 20 runs. Palette: "Show or Hide the
  Hook Output Panel".
* **Limits**: a hook that opens its own Terminal or app is not pulled in; only what it prints appears. Hooks cannot
  ask for input (a hook that waits fails instead of hanging). Colour codes are stripped; output is capped.
* **Timeout**: a push whose repository has a `pre-push` hook may take up to 30 minutes (`GitClient.hookTimeout`)
  instead of the usual 5, so a slow guardrail finishes and a hung one is still stopped. Cancel works either way.
* **Output cleaning**: colour codes and `\r` progress redraws are removed, also when one is split across two reads.
* **Push menu**: "Run pre-push hooks" (shown only when the repo has one). Off pushes with `--no-verify`; the choice
  is stored per repository in the app's preferences, a shield badge shows on the Push pill, and the Log notes it.
* **Commit**: the "Skip hooks" checkbox is `--no-verify` and is remembered per repository. Commit hook output goes to
  the same panel. With hooks skipped, `prepare-commit-msg` and `post-commit` still run (git does not skip them) and
  still show their output.

Code: `LFKit/GitHooks.swift`, `GitClient.push(runHooks:onOutput:)`, `Features/Hooks/`.
