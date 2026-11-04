# The Changes panel

`Changes/ChangesSidebar.swift` (the file list) + `ChangesViews.swift` (commit box and detail) + `ChangesModel.swift`.
The other layouts are in `Changes/Workspace/` (`ChangesWorkspace`, `InlineWorkspace`, `LanesWorkspace`,
`WorkingLane`, `BranchContextCard`, `WorkspacePanels`), the floating panels in `Changes/Floating/`, and the row in
`ChangeRow.swift`.

## Layouts (Settings › Layout › Changes)

The choice is `layout.changes` (`ChangesLayout`): **Classic** (default), **Inline preview** (`inline`) or **Lanes**
(`lanes`). The list, the staging and the commit are the same in all three; only the arrangement differs. Routing is in
[shell-ui.md](shell-ui.md) (*Layout settings*).

### Classic

```
┌ Changes card (sidebar, 280–480) ─┐ ┌ diff card ────────────────────────────┐
│ ListActionBar                     │ │ file name · Staged · Stage File   ⧉   │
│ Staged · n                        │ │ hunks …                               │
│ Changes · n                       │ │                                       │
│ CommitBox                         │ │                                       │
└───────────────────────────────────┘ └───────────────────────────────────────┘
```

The sidebar is the `NavigationSplitView` sidebar: both sections and the commit box at its bottom. The diff is the
detail.

### Inline preview (`InlineWorkspace`)

```
┌ changes card: 300 · 740 with a diff ─────────────┐ ┌ context card, 520 ──────────┐
│ Changes header                                    │ │ Commit: CommitBox           │
│ Staged · n / Changes · n  │ diff of the file  ✕   │ │ Branch: name ↑n ↓n Pull Push│
│ file                      │ hunks …               │ │ recent commits (8)          │
└──────────────────────────────────────────────────┘ └─────────────────────────────┘
```

* The list card holds the file list only. Clicking a file opens its diff inside the same card, which widens from
  300 to 740 pt (animated). ✕ on the diff closes it and the card shrinks back.
* The right card has the commit box and `BranchContextCard`: the checked-out branch, its upstream, ahead/behind,
  Pull and Push, and the latest commits (`commitLimit` 8). It is read-only here.

### Lanes (`LanesWorkspace`)

```
┌ Unstaged · n ─┐ ┌ dotted canvas, scrolls sideways ─────────────────────────────┐
│ file          │ │ ┌ working lane 340 ───────┐ ┌ panel 440 ──────┐   ┌──────┐  │
│ file          │ │ │ Staged · n  +a ~b −c    │ │ diff of a file   │   │ map  │  │
│ …             │ │ │ CommitBox               │ │ or a commit's    │   └──────┘  │
│               │ │ │ branch ↑ ↓ Pull Push    │ │ files and diff   │             │
│               │ │ │ ● Your commit goes here │ │                  │             │
│               │ │ │ ● recent commits (8)    │ │                  │             │
└───────────────┘ │ └─────────────────────────┘ └──────────────────┘             │
                  └──────────────────────────────────────────────────────────────┘
```

* **One working lane** (`WorkingLane`): the staged files, the commit box, and the checked-out branch with its latest
  commits. A "Your commit goes here" marker sits above the newest commit. LF-Git has no virtual branches, so there is
  only this one lane; there is no drop-to-assign.
* **Unstaged** is a card to the left of the canvas (`ChangesSidebar` with `sides: .unstaged`).
* **One detail panel** (`WorkspacePanels`) sits to the right of the lane. Clicking an unstaged or staged file opens its
  diff there; clicking a commit opens the commit's files and diff (`CommitPreviewPanel`, stacked because the panel is
  narrow). Opening one replaces the other, and ✕ closes it.
* **Minimap** (`lanes-minimap`): a pill at the bottom right, shown only when the canvas is wider than the view. A
  block per lane and per panel scrolls there.

## Floating panels (every layout)

`ChangesFloatingHost` wraps the Changes content in all layouts, Classic included. The panels only show while Changes
is on screen, and their state is kept while another section is open.

* **Pop Out Diff** (`pop-out-diff`, in the diff header) opens a floating panel, 860 × 627: the file list of the
  selected file's side (300 pt) beside its diff. The docked diff then shows "The diff is in a floating panel" with
  **Bring Back** (`dock-diff`).
* **Pop Out Commit Editor** (`pop-out-commit-editor`, in the commit box) opens a "Commit Message" panel, 620 × 300,
  with the commit box in it. The docked box then shows a notice with **Bring Back** (`dock-commit-editor`), so there
  is only ever one message editor and one ⌘↩.
* Panels are dragged by their header and stay inside the window. Their position is kept per window
  (`@SceneStorage`, see [shell-ui.md](shell-ui.md)).

## Sidebar

```
ListActionBar     tree/list toggle · Expand All · Collapse All
List (sidebar)
 ├─ Section "Staged · n"    (header button: Unstage All)
 │    └─ ChangeTreeRows  → folders (DisclosureGroup) → ChangeRow
 └─ Section "Changes · n"   (header button: Stage All)
CommitBox         message · Amend · Skip hooks · Commit     (Classic only; the other layouts place it themselves)
```

* The list is `List(selection:)` over `Set<ChangeSelection>`. Both sections are in the list while the tree is dirty,
  and the "No changes" message is an overlay on the list (see *Row identity*).
* `sides` (`ChangeSides`: both, staged, unstaged) fixes which sections a list shows, for the whole life of that list.
* `PathNode<Item>` (`Repository/PathTree.swift`) turns slash-separated paths into folders: folders first, each
  level sorted, a folder holding only another folder is shown as one row (`a/b/c`). `.items` returns every leaf
  under a node (used for the folder's stage/unstage button and its count). The same type builds branch trees.
* Open/closed state is `collapsed: Set<String>` with keys such as `section:staged`, `staged:src/`. Expand All
  clears it, Collapse All fills it from `allKeys`. The tree/list choice is `@AppStorage("changes.showsTree")`.
* A section shows at most 500 rows per page, then a "Show N more" link (`CappedRows`), so a very large change set
  does not stop the List.

## Row identity

The sidebar is a sidebar `List`, which AppKit backs with an outline view that reuses rows by identity. Several
things went wrong when identity was ambiguous (the "stage / unstage panel sometimes lays out wrong" bug):

* **Rows are identified by `ChangeSelection(path, staged, isFolder)`.** The same path can be in both sections
  (a folder such as `src/` can be staged and unstaged at once), so the section is part of the identity. `CappedRows`
  builds each row's id from it through a lazy map; a row that moves between sections is a different row, so it does
  not keep a stale highlight, disclosure state or position. Rows are tagged with the same `ChangeSelection`.
* **Both sections stay in the list while the tree is dirty.** Inserting or removing the first section shifted the
  second one, and the outline view misplaced its header and rows. An empty section shows only its header.
* **"No changes" is an `overlay`, not a row.** A row's height is cached by the list and went stale when the tree
  switched between clean and dirty.

## Selection

* One selected row → `pick(_:)` → `changes.select(_:)` loads that file's diff.
* Several selected rows are kept in `picked` for bulk staging; the detail pane keeps showing the last single one.
* `ChangesModel.statusDidChange` moves `selection` to the other section when a file is staged/unstaged, and
  `syncPicked()` makes the list follow it.
* `Binding(get:set:)` is built with `set: { pick($0) }` on purpose: passing the method (`set: pick`) crashes the
  Swift 6.2 compiler (IRGen). Keep the closure.
* The lookup of a selected file is `ChangesModel.change(for:)` → `ChangeListing.change(path:staged:)`. The listing
  builds a dictionary per side once per refresh (O(n)), so each lookup is O(1). It used to scan the whole status
  (O(n)) on every selection and refresh.

## Row (`ChangeRow`)

Status letter (`M A D R ?`), file name, optional folder / "from old name" subtitle, and a ± button
(`stage-<path>` / `unstage-<path>`). The context menu has Stage/Unstage, Discard Changes… (unstaged only,
confirmed), Ignore (`.gitignore` or `.git/info/exclude`), Stash This File, File History, Open File, Copy Path and
Show in Finder.

## Detail pane (`ChangesDetailView`)

Header (file name, diff options, *Staged / Not staged*, *Stage File / Unstage File*, Pop Out Diff, and ✕ when it is
a panel), the `LineSelectionBar` when lines can be picked, then `DiffContentView`. The header is a `ViewThatFits`:
actions go on a second row in a narrow panel. `canPickLines` and `hunkAction` decide which change kinds allow
line and hunk staging; see [staging.md](staging.md).

## Commit box (`CommitBox`) and `ChangesModel`

* `canCommit` = non-empty message, and (amend or something staged), and not already committing.
* The box wraps with `ViewThatFits`: one row (Amend, Skip hooks, Commit) when it fits. At the sidebar's minimum width
  (280 pt) the checkboxes go above the button instead of being squeezed.
* `setAmend(true)` pre-fills the last commit's message if the box is empty; turning it off removes it again, but
  only if the user did not change it (`prefilledMessage`).
* `commit()` runs `GitClient.commit(message:amend:noVerify:)` through the write queue, clears the box and refreshes.
* The "Detached HEAD" warning and the "on <branch>" caption are in the box too.

## Tests

`LF-GitTests/BranchesAndTreeTests.swift` (PathTree), `ModelTests.swift` / `GitClientModelTests.swift` (model
behaviour), `ChangeListingTests.swift` (the O(1) lookup by side), `ChangesWorkspaceTests.swift` (the panel state of
the Inline and Lanes layouts and the floating panels), `LazygitUITests` (Space, folders collapse/expand, stale rows).
