# The window shell: side menu, cards, toolbar, palette, shortcuts

## Layout (`Repository/RepositoryView.swift`)

```
HStack (window color: surfaceSunken)
 ├─ SectionRail                        (side menu, fixed width)
 └─ content, wrapped in ChangesFloatingHost (floating panels; Changes only)
      ├─ Changes + Classic             → NavigationSplitView (below)
      ├─ Changes + Inline / Lanes      → ChangesWorkspace (the whole content area, no split view)
      └─ every other section           → NavigationSplitView
           ├─ sidebar  → CardHeader + the list for repository.section, in a white card (.lfCard())
           └─ detail   → the matching detail in a card, with OperationBanner / BisectBanner on top
 + log panel (bottom inset, a card), toolbar pills, dialogs (RepositoryDialogs)
```

`repository.section` (`RepositorySection`, defined in `RepositoryModel.swift`) selects what both columns show.
The look follows the "Clean Plate" design (see README › Design credits); the plan is `plan/side-menu-redesign.plan.md`.
The layout choices (L1–L8) are in `.claude/plans/gitbutler-layout-redesign.plan.md`; the Inline and Lanes layouts of
Changes are described in [changes-panel.md](changes-panel.md).

## Layout settings (`Repository/Layout/LayoutPreferences.swift`, `Settings/LayoutSettingsTab.swift`)

Settings › Layout stores three choices in `@AppStorage`. Each is read by the views named below.

| Key | Values (enum) | Default | Read by |
|---|---|---|---|
| `layout.changes` | `classic`, `inline`, `lanes` (`ChangesLayout`) | `classic` | `RepositoryView`: anything but Classic shows `ChangesWorkspace` |
| `layout.lists` | `classic`, `threeColumn` (`ListsLayout`) | `classic` | `BranchesDetail`, `CommitListView` (day headers), `HistoryDetailView` (files │ diff) |
| `layout.timeline` | on / off (`LayoutPreferences.timelineDefault` = off) | off | `ReflogSidebar` (timeline rows) |

An unknown stored value reads as the default (`ChangesLayout(stored:)`, `ListsLayout(stored:)`). A layout changes
only the arrangement: the models, git commands and colors are the same in every layout.

## Shared layout pieces (`Repository/Layout/`)

* **`JoinedCards`**: two panes flush inside one card, split by a 1 pt hairline. The leading pane has a width range
  (default `Chrome.listColumn`…`listColumnMax`, 300–420). Used by the three-column Branches, the file list │ diff of
  `HistoryDetailView`, and the floating diff.
* **`CloseButton`** (`JoinedCards.swift`): the ✕ in card headers and panels. It has no Esc shortcut on purpose: a
  window-wide `.cancelAction` would close the panel while Esc belongs to the commit message or the palette.
* **`DayGrouping`** (`DayGrouping.swift`): `group(_:date:)` splits a list that is already in order into runs by day,
  titled *Today*, *Yesterday* or the date. One pass, O(m). A day that comes back after another starts a new group.
  `ReflogTimeline` (in `Lists/ListsLogic.swift`) uses it for the Reflog; `BranchScope` (All / Local / Remote) and
  `CurrentTarget` (the pinned summary row) are in the same file.
* **`HeroPane`** (`HeroPane.swift`): a title, a message, actions and a tinted symbol panel (480 pt). Under about
  800 pt wide, the panel moves under the text. Only the Dashboard's empty state uses it.
* **`FloatingPanel`** and **`FloatingPlacement`** (`Layout/Floating/`): a card with a ⠿ handle that drags it, a title
  and a ✕. It floats over the content area, stays 8 pt inside it, and remembers its position per window with
  `@SceneStorage` (`floating.<id>.x` / `.y`).
* **`Chrome`** (`CardStyle.swift`) sizes, measured in the Figma file: `listColumn` 300 (`listColumnMax` 420),
  `laneWidth` 340, `panelWidth` 440, `settingsSidebar` 240, `settingsContent` 580.

## Side menu (`Repository/SectionRail.swift`)

* `SideMenuSections(hasConflicts:selected:)` decides the order: Changes, Branches, History, a rule, then Stash, Tags,
  Remotes, Reflog, Worktrees, Submodules, and Conflicts **only while files are conflicted or it is selected**.
* `SideMenuTile` is a 34 pt outlined tile; selected, it is raised (`surfaceRaised`) with the icon in
  `railSelectedIcon`, and an `accentVivid` mark on the window edge follows it (`matchedGeometryEffect`).
  Counts come from `RepositoryModel.badgeCount(for:)` (changes, stashes, conflicted files), shared with `CardHeader`.
* The sections scroll when the window is short; the bottom group (log panel, Settings, Git account) stays put.
  The account button opens Settings on the Account tab (`SettingsTab`, `@AppStorage("settings.tab")`).
* Identifiers: container `section-picker`, tiles `section-<Name>`, bottom `log-button`, `settings-button`,
  `account-button`. UI tests switch sections with `showSection(_:in:)` in `GitUITestCase.swift`.

## Cards and pills (`Repository/CardStyle.swift`, `Repository/ToolbarPills.swift`)

`Chrome` holds the radii and gutter. `.lfCard()` (white, radius 10, hairline border), `CardHeader`, `CountCapsule`,
`DotGridBackground` (the canvas behind empty panes) and `EmptyPane`. `PillButtonStyle` (`.pill`, `.prominentPill`),
`.pillChrome()` for menus, and `PillGroup` + `PillDivider` for joined pills.

## Toolbar (`Repository/RepositoryToolbar.swift`)

Navigation: `RemoteButtons`: upstream │ last fetch (`RepositoryModel.lastFetchDate`, from `FETCH_HEAD`; click to
fetch, or progress + Cancel while busy), the copied-commits menu, a prominent **"N upstream commits"** pill (pull,
fast-forward only) while behind, and the Push menu with the ahead count. Centre: `ProjectMenu` (recent repositories,
open, close) joined to `BranchMenu` (popover with search). Trailing: New branch (⌘B, `requestNewBranch`), Commands
(⌘K), Close. `OperationBanner` (a stopped merge/rebase/cherry-pick: Continue, Skip, Abort) is in
`RepositoryToolbar.swift`; `BisectBanner` is in `RepositoryDialogs.swift`.

## Command palette (`Palette/PaletteActions.swift`)

`RepositoryModel.paletteActions(app:)` returns every `PaletteAction` (id, title, symbol, hint, enabled, closure);
`CommandPaletteView` filters them by words. Actions that are risky open a confirmation instead of acting. User
commands from the config file are appended by `customCommandActions`. `KeyboardHelpView` lists the shortcuts
(`⌘/`).

## Menus and shortcuts (`App/AppCommands.swift`)

⌘O open, ⌘S save, ⌘Z / ⇧⌘Z undo/redo a resolution, ⌘K palette, ⇧⌘L log, ⌘/ help, ⌃1…⌃0 sections,
⌥⌘F/L/P fetch/pull/push, ⌥⌘Z undo last git move, ⌥⌘↓/↑ next/previous conflict, ⌘1…⌘4 accept choices. Commands reach the
focused window through `FocusedValues.swift` (`repositoryModel`, `editorModel`).

## Dialogs (`Repository/RepositoryDialogs.swift`)

`RepositoryModel` publishes `prompt` (`PendingPrompt`, a text answer), `confirmation` (`PendingConfirmation`, yes/no)
and `messageEdit` (`PendingMessageEdit`, multi-line); this modifier turns each into an alert or sheet. Use `repository.ask(_:)`, `confirm(_:)` and
`app.run { }` instead of presenting UI from a model.

## Accent color

Settings > Theme > *Accent color* stores `AccentSetting.storageKey` (`accentColor`) in `UserDefaults`.

* `Design/theme.json` → `accentChoices` lists the colors; `LFCore/Scripts/gen_theme.py` writes one color set per
  choice (`lfAccentBlue` …) and the `LFAccentChoice` enum, and checks contrast for each choice.
* `LFThemeToken.assetName(for:)` (`Theme/LFTheme.swift`) is the single place that picks the color set: accent tokens
  get the choice's suffix, every other token is unchanged. `Color(theme:)` and `NSColor.theme(_:)` both use it.
* `Theme/AccentSync.swift` (`syncsAccent`) re-tints the window and gives the main window a new identity when the
  choice changes, so every view and AppKit table rebuilds with the new color. Models are not affected; transient
  view state (open folders, line selection) is reset. Settings only re-tints, so unsaved edits there survive.

## Settings window (`Settings/SettingsView.swift`)

A sidebar (`SettingsSidebar`, 240 pt) beside one scrolling column of section cards (`SettingsPage` and
`SettingsCard` in `SettingsCards.swift`, 580 pt), in a window of about 844 × 560. The tabs are `SettingsTab`
(`SettingsTabs.swift`), in this order: **General**, **Account**, **Network**, **Environment**, **Theme**, **Layout**.
Each sidebar row has the identifier `settings-tab-<rawValue>`. The selected tab is `@AppStorage("settings.tab")`, so
the Account button in the side menu still opens the Account tab.

* **Layout** (`LayoutSettingsTab.swift`): three cards with the choices above: *Changes* (`layout-changes-picker`),
  *Lists* (`layout-lists-picker`) and *Reflog* as a timeline (`layout-timeline-toggle`).
* The other tabs (`SettingsTabs.swift`): `GeneralSettingsTab` (reopen the last repository), `AccountSettingsTab`,
  `NetworkSettingsTab`, `EnvironmentSettingsTab` and `ThemeSettingsTab`, each a `SettingsPage` of `SettingsCard`s.

## Welcome and theme

`Settings/` also holds the accounts, git config and terminal environment sections, `Welcome/` (recent repositories,
preview of a conflict), `Theme/` (`LFThemeToken.generated.swift` from `Design/theme.json`, light/dark/system via
`AppearanceSetting`).

## Previews

`Preview/PreviewRepository.swift` (debug only) builds a sample repository so every view has a working SwiftUI
preview. List new views' previews in the README's *Redesigning the UI in Xcode* table.
