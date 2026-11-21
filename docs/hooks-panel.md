# Hooks panel

Hooks that a push or commit runs print into a panel inside LF-Git instead of leaving that to terminal windows.

* **Panel**: opens above the Log panel when a push or commit starts and the repository has a matching hook
  (`pre-push`; `pre-commit`, `prepare-commit-msg`, `commit-msg`, `post-commit`). It shows live output, a status chip
  (running / passed / failed with time), Copy, Clear and a picker for the last 20 runs. Palette: "Show or Hide the
  Hook Output Panel".
* **Terminal actions**: guardrail hooks that launch a script in Terminal run it inside the hook instead, and its
  output appears in the panel between `── Terminal action: … ──` and `── finished (exit N) ──`. No Terminal window
  opens. LF-Git puts stand-ins for `open` and `osascript` first on the hooks' `PATH`
  (`~/Library/Application Support/LF-Git/hook-shims`). Caught: `open -a Terminal|iTerm|Warp|Ghostty <script>` (also
  by app path or `-b` bundle id, with `--args`), `open <file>.command|.tool`, and
  `osascript -e 'tell application "Terminal" to do script "…"'` / iTerm `write text "…"`. Anything else is passed to
  the real command unchanged. The action runs to completion before the hook continues and never fails the hook
  (the real `open` returns 0 at once). Settings › General › Hooks turns it off.
* **Limits**: a hook that calls `/usr/bin/open` by full path, or launches Terminal some other way, still opens it.
  Hooks and their actions get no keyboard input (a hook that waits fails instead of hanging). Colour codes are
  stripped; output is capped.
* **Timeout**: a push whose repository has a `pre-push` hook may take up to 30 minutes (`GitClient.hookTimeout`)
  instead of the usual 5, so a slow guardrail finishes and a hung one is still stopped. Cancel works either way.
* **Output cleaning**: colour codes and `\r` progress redraws are removed, also when one is split across two reads.
* **Push menu**: "Run pre-push hooks" (shown only when the repo has one). Off pushes with `--no-verify`; the choice
  is stored per repository in the app's preferences, a shield badge shows on the Push pill, and the Log notes it.
* **Commit**: the "Skip hooks" checkbox is `--no-verify` and is remembered per repository. Commit hook output goes to
  the same panel. With hooks skipped, `prepare-commit-msg` and `post-commit` still run (git does not skip them) and
  still show their output.

Code: `LFKit/GitHooks.swift`, `GitClient.push(runHooks:onOutput:)`, `Features/Hooks/`.
