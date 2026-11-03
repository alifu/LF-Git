# Plan: Side-menu redesign ("Clean Plate")

**Source design**: `~/Downloads/clean_plate.svg` (1588×888, light mode only)
**Replaces**: the Office-2007-style `SectionRibbon`
**Complexity**: Large (window shell, theme palette, tests, docs, screenshots)
**Status**: approved 2026-11-03, implemented; visual check pending (screenshot tour must be run locally)

## Decisions (2026-11-03: "yes" to every recommendation)

1. Teal is the default accent; green stays selectable (`accentChoices`: teal, green, blue, purple, orange).
2. Filled buttons: white text on deep teal `#178080` (4.7:1); bright `#25B1B1` is `accentVivid` (side-menu mark,
   dark-mode accent).
3. Native `NavigationSplitView` kept, columns styled as cards.
4. Conflicts appears in the side menu only while files are conflicted (or while it is selected).
5. Side-menu bottom: Log panel, Settings, Git account (opens Settings › Account).
6. Dashboard: new palette only, no side menu.
7. Design source credited in README › Design credits (GitButler Desktop 3.5, Figma Community, CC BY 4.0).

## Summary

Swap the ribbon across the top of the repository window for a narrow **icon rail on the left**, and restyle the
window to the mockup: a warm stone-grey window, white rounded **cards** for the list and detail panes, and a **teal**
accent. The toolbar becomes a row of rounded "pill" controls, as in the mockup. `RepositorySection` and every
sidebar and detail view keep their behaviour. Only the shell around them and the palette change.

## What the mockup shows

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  [⟲ origin/main │ ⇅ 1 min ago] [3 upstream commits]   [▣ Project ⌃│⑂ branch]  [+ New branch ⌘B][✦] │
├──┬──────────────────────┬───────────────────────────────────────────────────────────────────┤
│▌▣│ ◫ Unassigned  (0)    │ · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · │
│ ⑂│──────────────────────│ · · · · · · · ·  dotted canvas, empty-state in the middle · · · · │
│ ⟲│                      │ · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · │
│  │   (empty state)      │ · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · │
│ ⚙│──────────────────────│ · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · │
│ ◉│ › Rules (0)        + │ · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · │
│ ✉│                      │                                                                   │
└──┴──────────────────────┴───────────────────────────────────────────────────────────────────┘
```

* **Rail** (≈34 pt icon tiles, 8 pt gap): selected tile is white with a hairline border and a coloured icon;
  the others are outlined tiles with a grey icon. A small **teal pill on the window's left edge** marks the
  selection. Settings, the account avatar (filled teal circle) and a mail icon sit at the bottom.
* **List card**: white, radius ≈10, 1 pt border. Header row with an icon, a title and a dark **count capsule**.
  Footer row with a disclosure, a title, a count and a "+".
* **Detail canvas**: window colour with a faint **dot grid**, a hairline border, and a centred empty state
  (title in dark text, body in subtle text, inline links underlined).
* **Toolbar**: outlined pills. The status pill shows remote and last fetch. A **filled teal** call-to-action shows
  "N upstream commits". The centred pill is a project switcher joined to a branch pill. On the right are
  "New branch ⌘B" and an icon button.

### Palette taken from the SVG

| Hex | Where it is used in the mockup | Proposed token |
|---|---|---|
| `#F3F2F1` | window, toolbar, canvas, card headers | `background` (window) / `surfaceSunken` |
| `#FFFFFF` | list card body, selected rail tile | `surfaceRaised` |
| `#CAC6C3` | card + pill borders | `border` |
| `#AAA29D` | dot grid, disabled/placeholder icons | **new** `borderStrong` (decorative only) |
| `#7C716A` | secondary text, inactive icons | `textSubtle` *(needs a small darken, see Risks)* |
| `#272321` | primary text, count capsules | `text` |
| `#1C1917` / `#3A3532` | darkest ink, capsule fill | dark-mode surfaces (see below) |
| `#25B1B1` | upstream button, avatar, rail marker | `accent` (teal) |
| `#9FE4E4` | illustration highlight | `accentSubtle` (dark variant), decorative |
| `#FF9774` / `#D96842` | coloured icon in the selected tile | **new** `railSelectedIcon` |

The mockup is **light only**. For dark mode I'll derive a warm palette from the same family: window `#1C1917`,
cards `#272321`, border `#3A3532`, text `#F3F2F1`, subtle `#AAA29D`, accent `#25B1B1`. Teal on `#1C1917` is 6.7:1,
which passes.

> I'm taking the layout and colours only. The mockup looks like a GitButler screen ("gitbutler/workspace",
> "Unassigned", "Rules"). I won't copy its illustrations, logo, wording or GitButler-only concepts such as
> "Unassigned" and "Rules". LF-Git keeps its own sections and copy, and empty states use SF Symbols.

## Patterns to mirror

| Category | Source | Pattern |
|---|---|---|
| Colour | `LF-Git/Theme/LFTheme.swift:4` | Views use semantic tokens only (`.theme(.x)`). Hex lives in `Design/theme.json`, and `LFCore/Scripts/gen_theme.py` generates the colour sets plus `LFThemeToken.generated.swift` |
| Contrast gate | `.github/workflows/ci.yml:58`, `gen_theme.py:110` | `gen_theme.py --check` fails CI below 4.5:1 for every pair in `contrast.pairs`, for every accent choice |
| Section switch | `RepositoryModel.swift:26`, `SectionRibbon.swift:130` | `RepositorySection` enum (name + SF Symbol); a button sets `repository.section` |
| Counts | `SectionRibbon.swift:148` | `count(_:)`: changes, stashes, conflicted files |
| Accessibility ids | `SectionRibbon.swift:55,199` | container `section-picker`, buttons `section-<Name>`; `GitUITestCase.showSection` depends on them |
| Persisted UI state | `SectionRibbon.swift:8` | `@AppStorage("…")` |
| Previews | `SectionRibbon.swift:221` | `#Preview` with `PreviewRepository(width:height:)` |
| UI tests | `LF-GitUITests/LazygitUITests.swift:205` | XCUITest with `item(app, id)` and `waitForExistence` |
| Project files | `project.pbxproj` | File-system-synchronised groups, so new files need no pbxproj edits |

## Files to change

| File | Action | Why |
|---|---|---|
| `Design/theme.json` | UPDATE | Add the warm palette, repoint the neutral tokens, add `borderStrong` and `railSelectedIcon`, update the teal accent choice, and add contrast pairs |
| `LF-Git/Assets.xcassets/Theme/*`, `LF-Git/Theme/LFThemeToken.generated.swift` | REGENERATE | Run `gen_theme.py` (never hand-edit these) |
| `LF-Git/Theme/LFTheme.swift` | UPDATE | Change the default accent if we decide on teal (Q1) |
| `LF-Git/Features/Repository/SectionRail.swift` | CREATE | Rail view, `RailButton`, edge marker, badges, bottom group |
| `LF-Git/Features/Repository/CardStyle.swift` | CREATE | `.lfCard()` modifier (white, radius 10, border), `CardHeader` (icon, title, count capsule), `DotGridBackground` |
| `LF-Git/Features/Repository/ToolbarPills.swift` | CREATE | `PillButtonStyle` (outlined), `ProminentPillButtonStyle` (teal), `PillGroup` (joined pills with divider) |
| `LF-Git/Features/Repository/RepositoryView.swift` | UPDATE | `HStack { SectionRail; split }`, cards around sidebar and detail, dot-grid canvas, restyled toolbar items |
| `LF-Git/Features/Repository/RepositoryToolbar.swift` | UPDATE | `RemoteButtons` → status pill + "N upstream commits" CTA + push/pull menus; `BranchMenu` → joined pill; project switcher from `app.recentRepositories` |
| `LF-Git/Features/Repository/RepositoryModel.swift` | UPDATE | `RepositorySection.railGroup` (primary / more), so the rail order lives with the enum |
| `LF-Git/Features/Repository/SectionRibbon.swift` | DELETE | Replaced by the rail (`WrappingLayout` isn't used anywhere else) |
| Sidebars (`ChangesSidebar`, `BranchesViews`, `HistoryViews`, `StashViews`, `TagsReflogViews`, `RemotesViews`, `WorktreesSubmodulesViews`, `ConflictsSidebar`) | UPDATE (light) | Drop `.listStyle(.sidebar)` material so the white card shows; use `CardHeader` where a section title exists |
| Empty states (`RepositoryView.swift` detail, `ChangesViews`, `HistoryViews`) | UPDATE | Centred empty state on the dot grid, in the mockup's text styles |
| `LF-Git/Features/Welcome/DashboardView.swift`, `RecentRepositoryRow.swift` | UPDATE | Same palette, cards and pills; no rail (no repository is open yet) |
| `LF-Git/LF_GitApp.swift` | UPDATE | `.windowToolbarStyle(.unified)`, toolbar background = `background` token, hidden title |
| `LF-Git/Features/Settings/SettingsView.swift` | UPDATE | Accent picker: new teal swatch / default (Q1) |
| `LF-GitUITests/LazygitUITests.swift:205-214` | UPDATE | Replace ribbon-collapse test with a rail test (every section reachable, selection marker follows) |
| `LF-GitUITests/ScreenshotTourUITests.swift:66-70` | UPDATE | Drop the `ribbon-minimized` shot; add a `side-menu` shot |
| `LF-GitUITests/GitUITestCase.swift:31` | KEEP / verify | `showSection` keeps working because the ids stay the same |
| `LF-GitTests/ThemeTests.swift` | UPDATE | Cover new tokens and the default-accent change |
| `docs/shell-ui.md`, `docs/README.md`, `README.md` | UPDATE | Document the rail instead of the ribbon and retake the screenshots |

## Tasks

### Phase 1: Palette (no layout changes yet)

**Task 1.1: Warm neutrals and teal in `theme.json`**
- **Action**: Add `Stone*` palette entries from the SVG, plus dark counterparts. Repoint `background`,
  `surfaceSunken`, `surfaceRaised`, `border`, `text` and `textSubtle`. Add `borderStrong` and `railSelectedIcon`.
  Retune the `teal` accent choice to `#25B1B1`. Add contrast pairs `text/background` and `textSubtle/background`
  for the new window colour.
- **Keep unchanged**: diff, conflict, syntax and minimap tokens. They sit on the white editor and already pass.
- **Validate**: `python3 -I LFCore/Scripts/gen_theme.py && python3 -I LFCore/Scripts/gen_theme.py --check`
- **Test first**: update `ThemeTests` to expect the new tokens and fail (RED) before regenerating.

**Task 1.2: Fix contrast where the mockup's colours fail**
- `#7C716A` on `#F3F2F1` = **4.24:1** (fails). Darken to ≈`#70655E` (keeps the hue).
- White on `#25B1B1` = **2.62:1** (fails). See Q2.
- **Validate**: `gen_theme.py --check` is green for every accent choice.

### Phase 2: Shared building blocks

**Task 2.1: `CardStyle.swift`**: `.lfCard()`, `CardHeader(title:symbol:count:)` with a dark count capsule
(`text` fill, `onAccent`-style light digits) and `DotGridBackground` (a `Canvas` that draws `borderStrong` dots on a
6 pt grid, sized to the view and cheap to redraw).
**Task 2.2: `ToolbarPills.swift`**: outlined pill style (height 26, radius 6, border token, `surfaceRaised` on
hover), a prominent teal style, and `PillGroup` for joined pills with a hairline divider.
- **Mirror**: token-only colours and `#Preview` blocks like `SectionRibbon.swift:221`.
- **Validate**: build and check previews in light and dark.

### Phase 3: The rail

**Task 3.1: `RepositorySection.railGroup`**
- Primary (top): Changes, Branches, History. More (below a hairline): Stash, Tags, Remotes, Reflog, Worktrees,
  Submodules. Conflicts goes at the end with a danger badge, and only shows **while there are conflicts** (Q4).
- **Test**: a unit test that every case belongs to exactly one group.

**Task 3.2: `SectionRail.swift`**
- 34 pt tiles in a `ScrollView` with no indicators, so 10 sections fit the 480 pt minimum height. The bottom group
  (Settings ⌘, Log panel toggle, Close repository) is pinned and does not scroll.
- Selected tile: `surfaceRaised` fill with a `border` stroke and the icon in `railSelectedIcon`. A 4×20 pt `accent`
  capsule sits on the window's leading edge, animated with `matchedGeometryEffect`.
- Badges: a small count capsule on the tile's top-trailing corner (reuse `count(_:)`).
- Accessibility: container id `section-picker`; each button keeps id `section-<Name>`, label = name,
  `.isSelected` trait and a `.help` tooltip. Keyboard: ⌘1…⌘9 if they're not already bound (check `AppCommands.swift`).
- **Validate**: UI test `testSideMenuSwitchesEverySection` (RED first, then implement).

**Task 3.3: Wire into `RepositoryView`**
- `HStack(spacing: 0) { SectionRail; content }` on the `background` token.
- Content: keep `NavigationSplitView` but hide its sidebar material (`.scrollContentBackground(.hidden)`,
  `.background(.theme(.background))`) and wrap each column in `.lfCard()` with 8 pt insets. If the split view
  fights the card look, fall back to `HSplitView` (see Q3).
- Detail: `DotGridBackground` behind the empty states. Real content (diff, graph, editor) stays on the white card.
- Delete `SectionRibbon.swift` and the `ribbon.isCollapsed` default.

### Phase 4: Toolbar

**Task 4.1**: Restyle `RemoteButtons` as a status `PillGroup` (remote name │ last fetch, relative time). Fetch
moves into this pill's click/menu. Show a teal **"N upstream commits"** CTA only when behind > 0, which pulls on
click. Push stays a pill with an ahead count.
**Task 4.2**: Centre a `PillGroup` with a project switcher (recent repositories from `app.recentRepositories` plus
"Open…" and "Clone…") and the `BranchMenu` pill.
**Task 4.3**: Trailing: "New branch ⌘B" pill and an icon pill for the command palette (⌘K). Reload, Log and Close
move to the rail bottom or the palette.
- **Validate**: existing UI tests that use `log-button`, `palette-button` and `close-repository-button` still find
  them (keep the ids wherever they end up).

### Phase 5: Sidebars, empty states and dashboard

**Task 5.1**: Remove sidebar material from each sidebar list and add `CardHeader` titles with counts.
**Task 5.2**: Write empty states in the mockup's typography: semibold title in `text`, body in `textSubtle`, and
underlined inline actions, e.g. "create a new branch +".
**Task 5.3**: Dashboard: same window colour and cards, with the pills for Open/Clone.

### Phase 6: Tests, docs and screenshots

- Update `LazygitUITests` and `ScreenshotTourUITests`, and run the full UI suite in light and dark with each accent.
- Rewrite the ribbon section of `docs/shell-ui.md`, update the `README.md` "Ribbon" paragraph and images, and
  update the `docs/README.md` index.
- Run the ecc:code-reviewer and ecc:swift-reviewer agents on the diff.

## Validation

```bash
python3 -I LFCore/Scripts/gen_theme.py --check
xcodebuild -project LF-Git.xcodeproj -scheme LF-Git -destination 'platform=macOS' build
xcodebuild -project LF-Git.xcodeproj -scheme LF-Git -destination 'platform=macOS' test -only-testing:LF-GitTests
xcodebuild -project LF-Git.xcodeproj -scheme LF-Git -destination 'platform=macOS' test -only-testing:LF-GitUITests
(cd LFCore && swift test)
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Mockup colours fail the CI contrast gate (subtle text 4.24:1, white on teal 2.62:1) | Certain | Small darkening of subtle text; Q2 for the teal button |
| `NavigationSplitView` sidebar material and toolbar insets clash with the card look | High | Hide the material first; fall back to `HSplitView` (loses the built-in sidebar toggle and column-width restore) |
| 10 sections plus the bottom group overflow at the 480 pt min height | Medium | Scrollable section group; Conflicts shown only when present |
| Neutral repoint changes every screen, including the conflict editor's surroundings | Medium | Diff/conflict/syntax tokens untouched; screenshot tour in light, dark and all accents before merging |
| Dark mode isn't in the mockup, so taste risk | Medium | Derived warm palette; I'll show screenshots for your sign-off in Phase 1 |
| Changing the default accent from green alters existing users' look | Low | Only users still on the default are affected; Q1 |
| UI tests depend on ribbon ids | Low | Keep `section-picker` / `section-<Name>`; remove only `ribbon-toggle` / `ribbon-tab` tests |
| Copying third-party artwork | Low | Layout and colours only; SF Symbols for icons and empty states |

## Open questions for review

1. **Accent default**: should teal `#25B1B1` become the **default** accent (green stays selectable), or should teal
   stay one choice among five with green as the default? *Recommendation: teal default, since the design is
   built around it.*
2. **Teal button text**: the white "3 upstream commits" text fails contrast. Options: (a) use dark text `#1C1917` on
   `#25B1B1` (6.7:1, same teal); (b) keep white text on a deeper teal `#178080` (4.7:1). *Recommendation: (b)
   for filled buttons, and keep `#25B1B1` for the rail marker, avatar and dark mode.*
3. **Split view**: keep `NavigationSplitView` (native, may look less like the mockup) or switch to a custom
   `HSplitView` (pixel-closer, loses the native sidebar toggle)? *Recommendation: try native first.*
4. **Conflicts in the rail**: always show it, or only while conflicts exist? *Recommendation: only while present.*
5. **Bottom of rail**: the mockup has Settings, an account avatar and mail. LF-Git has no inbox. Proposal: Settings,
   Git account (opens Settings ▸ Accounts) and the Log panel toggle.
6. **Dashboard**: restyle with the palette only (as planned), or show the rail there too (with Clone/Open/Recent
   as rail items)?

**WAITING FOR CONFIRMATION**: approve, or reply with changes (e.g. "Q1: keep green", "skip Phase 5").
