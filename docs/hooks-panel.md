# Hooks panel

What a push or commit's hooks print shows in a panel inside the window, and guardrail hooks that would open Terminal
run their check in place. The user-facing description is in the [README](../README.md) (*Hooks panel*).

## What happens on a push

```
Push (⌥⌘P / pill)
  └─ RepositoryModel.push                         Repository/RepositoryModel+Hooks.swift
       ├─ withHookRun("Push", ["pre-push"])        opens a HookRun + the panel, only if the hook exists
       ├─ hookShims()                              writes the open/osascript stand-ins (off main), if the setting is on
       └─ perform → GitClient.push(runHooks:hookShims:onOutput:)
            └─ git push  ── PATH = shims:…  ──▶ pre-push hook ──▶ `open -a Terminal check.command`
                                                                    └─ shim runs check.command here
            stdout + stderr of git and hooks ─▶ onOutput ─▶ HookOutputBuffer ─▶ HookRunStore ─▶ HooksPanelView
```

A commit takes the same path through `ChangesModel.commit` with the commit hooks.

## Pieces

| Piece | File | Does |
|---|---|---|
| Hook discovery | `LFKit/GitHooks.swift` | `hooks()` lists the hooks directory (`git rev-parse --git-path hooks`, so `core.hooksPath`, husky and lefthook count), skipping `*.sample`; `hasHook(named:)`, `hasHook(namedAnyOf:)`. Runs git: call it off the main actor |
| Output capture | `LFKit/Git.swift` (`combineOutput`), `GitClient.push` / `commit` (`onOutput`) | git's stdout goes into the stderr file, in order, and is streamed by `StandardErrorTailer`. Needed because `pre-push` hooks write to stdout |
| Skipping hooks | `GitClient.push(runHooks:)`, `commit(noVerify:)` | `--no-verify`. `prepare-commit-msg` and `post-commit` still run (git's rule) |
| Time limit | `GitClient.hookTimeout` | a push that runs a `pre-push` hook gets 30 min instead of 5; Cancel works either way |
| Terminal actions | `LFKit/HookShims.swift` | the `open` and `osascript` stand-in scripts, `install(in:)`, `path(prepending:to:)` |
| Run store | `Hooks/HookRun.swift` | `HookRun` (immutable; output, state, times, 400 000-character cap, colour-code and `\r` cleaning that survives a split between two reads) and `HookRunStore` (last 20 runs) |
| Wiring | `Repository/RepositoryModel+Hooks.swift` | `withHookRun`, `push`, `hookShims()`, `HookOutputBuffer` (drained before a run's status is set, so the last lines always land first) |
| Panel | `Hooks/HooksPanelView.swift` | header (status, run menu, Copy, Clear, Close) and auto-scrolling output; above the log panel in `RepositoryView` |
| Preferences | `Hooks/HookPreferences.swift` | per repository: push hooks off, commit hooks skipped; app-wide: Terminal actions inline (on by default) |
| Push menu | `Repository/RepositoryToolbar.swift` (`pushMenu`) | *Run pre-push hooks* (only when `hasPrePushHook`), *Show Hook Output*, the shield badge, the force-push warning |

`RepositoryModel.hasPrePushHook` comes from the off-main refresh snapshot, never from a git call on the main actor.

## The Terminal stand-ins

`HookShims.install()` writes two `sh` scripts to `~/Library/Application Support/LF-Git/hook-shims` (only when their
content changed), and push/commit put that folder first on the hooks' `PATH`.

| The hook runs | The stand-in |
|---|---|
| `open -a Terminal\|iTerm\|iTerm2\|Warp\|Ghostty <file>` (name or `.app` path), `open -b <terminal bundle id> <file>`, with `-n -g -F -W` and `--args …` | runs `<file>` with the arguments, in the hook's folder |
| `open <file>.command` / `.tool` | runs `<file>` |
| `osascript -e …` telling `Terminal` / `iTerm` / `iTerm2` to `do script "…"` / `write text "…"` (one or several `-e`) | runs each command with `$SHELL -c` |
| anything else (a URL, another app, a directory, an unknown option, a script it cannot read for certain) | `exec`s the real `/usr/bin/open` / `/usr/bin/osascript` with the same arguments |

The action runs in the foreground between `── Terminal action: … ──` and `── finished (exit N) ──`, and the stand-in
exits 0 whatever the action returned, as the real command does, so the hook's own logic is unchanged.
`LFGIT_REAL_OPEN` / `LFGIT_REAL_OSASCRIPT` override the real commands (tests use a recorder).

Limits: a hook that calls `/usr/bin/open` by full path, or sets its own `PATH` first, still opens Terminal. Actions get
no keyboard input. A long-running action holds the push until the time limit.

## Tests

| Covers | Tests |
|---|---|
| hook listing, `combineOutput`, `--no-verify` | `LFCoreTests/GitHooksTests.swift` |
| each stand-in form, pass-through, exit status, spaces in paths | `LFCoreTests/HookShimsTests.swift` (never reaches Terminal: the real commands are a recorder) |
| run store, cleaning, cap, preferences | `LF-GitTests/HookRunTests.swift` |
| push with a rejecting hook, hooks off, no hook, Skip hooks, a Terminal action | `LF-GitTests/HookPushModelTests.swift` |
| the panel on a real push whose hook runs `open -a Terminal` | `LF-GitUITests/PushHooksUITests.swift` (fixtures in `LF-GitUITests/Fixtures/guardrail-hooks`) |
