# The window shell: ribbon, toolbar, palette, shortcuts

## Layout (`Repository/RepositoryView.swift`)

```
VStack
 ├─ SectionRibbon                      (full width)
 └─ NavigationSplitView
      ├─ sidebar  → the list for repository.section (Changes, Branches, …, Conflicts)
      └─ detail   → the matching detail, with OperationBanner / BisectBanner on top
 + log panel (bottom inset), toolbar, dialogs (RepositoryDialogs)
```

`repository.section` (`RepositorySection`, defined in `RepositoryModel.swift`) selects what both columns show.

## Section ribbon (`Repository/SectionRibbon.swift`)

Office-2007 style. **Main**: Changes and History as big buttons; **Browse**: the other sections as medium
buttons in columns of three; a vertical rule between the groups; captions underneath.

* `WrappingLayout` (private `Layout`) fills the width offered and wraps groups to a new row, left aligned.
* `RibbonButton` has three sizes (`big`, `medium`, `small`); the whole frame is clickable (`contentShape`).
  Counts come from `count(_:)` (changes, stashes, conflicted files).
* Minimize: double-click the *Repository* tab or the arrow at the bottom right; minimized, the tab strip shows one
  small button per section. State: `@AppStorage("ribbon.isCollapsed")`.
* Identifiers: container `section-picker`, buttons `section-<Name>`, tab `ribbon-tab`, arrow `ribbon-toggle`.
  UI tests switch sections with `showSection(_:in:)` in `GitUITestCase.swift`.

## Toolbar (`Repository/RepositoryToolbar.swift`)

`BranchMenu` (popover with search), `RemoteButtons` (progress + Cancel, copied-commits menu, Fetch, Pull menu,
Push menu with ahead/behind counts), Reload, Log, Commands. `OperationBanner` (a stopped merge/rebase/cherry-pick: Continue, Skip, Abort) is in `RepositoryToolbar.swift`;
`BisectBanner` is in `RepositoryDialogs.swift`.

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
