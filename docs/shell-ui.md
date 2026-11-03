# The window shell: side menu, cards, toolbar, palette, shortcuts

## Layout (`Repository/RepositoryView.swift`)

```
HStack (window color: surfaceSunken)
 ├─ SectionRail                        (side menu, fixed width)
 └─ NavigationSplitView
      ├─ sidebar  → CardHeader + the list for repository.section, in a white card (.lfCard())
      └─ detail   → the matching detail in a card, with OperationBanner / BisectBanner on top
 + log panel (bottom inset, a card), toolbar pills, dialogs (RepositoryDialogs)
```

`repository.section` (`RepositorySection`, defined in `RepositoryModel.swift`) selects what both columns show.
The look follows the "Clean Plate" design (see README › Design credits); the plan is `plan/side-menu-redesign.plan.md`.

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

## Settings, welcome, theme

`Settings/` (accounts, git config, terminal environment, appearance), `Welcome/` (recent repositories, preview
of a conflict), `Theme/` (`LFThemeToken.generated.swift` from `Design/theme.json`, light/dark/system via
`AppearanceSetting`).

## Previews

`Preview/PreviewRepository.swift` (debug only) builds a sample repository so every view has a working SwiftUI
preview. List new views' previews in the README's *Redesigning the UI in Xcode* table.
