# The Changes panel

`Changes/ChangesSidebar.swift` (left) + `ChangesViews.swift` (commit box and detail) + `ChangesModel.swift`.

## Sidebar layout

```
ListActionBar     tree/list toggle · Expand All · Collapse All
List (sidebar)
 ├─ Section "Staged · n"    (header button: Unstage All)
 │    └─ ChangeTreeRows  → folders (DisclosureGroup) → ChangeRow
 └─ Section "Changes · n"   (header button: Stage All)
CommitBox         message · Amend · Skip hooks · Commit
```

* The list is `List(selection:)` over `Set<ChangeSelection>` (`path` + `staged`). The same path can be a row in
  both sections, so every row has `.tag(...)` **and** `.id(ChangeSelection)`; the id keeps a row that moved
  between sections from leaving a stale highlight behind.
* `PathNode<Item>` (`Repository/PathTree.swift`) turns slash-separated paths into folders: folders first, each
  level sorted, a folder holding only another folder is shown as one row (`a/b/c`). `.items` returns every leaf
  under a node (used for the folder's stage/unstage button and its count). The same type builds branch trees.
* Open/closed state is `collapsed: Set<String>` with keys such as `section:staged`, `staged:src/`. Expand All
  clears it, Collapse All fills it from `allKeys`. The tree/list choice is `@AppStorage("changes.showsTree")`.

## Selection

* One selected row → `pick(_:)` → `changes.select(_:)` loads that file's diff.
* Several selected rows are kept in `picked` for bulk staging; the detail pane keeps showing the last single one.
* `ChangesModel.statusDidChange` moves `selection` to the other section when a file is staged/unstaged, and
  `syncPicked()` makes the list follow it.
* `Binding(get:set:)` is built with `set: { pick($0) }` on purpose: passing the method (`set: pick`) crashes the
  Swift 6.2 compiler (IRGen). Keep the closure.

## Row (`ChangeRow`)

Status letter (`M A D R ?`), file name, optional folder / "from old name" subtitle, and a ± button
(`stage-<path>` / `unstage-<path>`). The context menu has Stage/Unstage, Discard Changes… (unstaged only,
confirmed), Ignore (`.gitignore` or `.git/info/exclude`), Stash This File, File History, Open File, Copy Path and
Show in Finder.

## Detail pane (`ChangesDetailView`)

Header (file name, diff options, *Staged / Not staged*, *Stage File / Unstage File*), the `LineSelectionBar` when
lines can be picked, then `DiffContentView`. `canPickLines` and `hunkAction` decide which change kinds allow
line and hunk staging; see [staging.md](staging.md).

## Commit box (`CommitBox`) and `ChangesModel`

* `canCommit` = non-empty message, and (amend or something staged), and not already committing.
* `setAmend(true)` pre-fills the last commit's message if the box is empty; turning it off removes it again, but
  only if the user did not change it (`prefilledMessage`).
* `commit()` runs `GitClient.commit(message:amend:noVerify:)` through the write queue, clears the box and refreshes.
* The "Detached HEAD" warning and the "on <branch>" caption are in the box too.

## Tests

`LF-GitTests/BranchesAndTreeTests.swift` (PathTree), `ModelTests.swift` / `GitClientModelTests.swift` (model
behaviour), `LazygitUITests` (Space, folders collapse/expand, stale rows).
