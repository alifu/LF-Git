import AppKit
import Testing
@testable import LF_Git

@MainActor
@Suite("Theme tokens")
struct ThemeTokenTests {
    @Test("every token resolves to a color set in the app bundle", arguments: LFThemeToken.allCases)
    func tokenResolves(token: LFThemeToken) {
        #expect(NSColor(named: token.rawValue) != nil)
    }

    @Test("every token has distinct light and dark values", arguments: LFThemeToken.allCases)
    func tokenHasDarkVariant(token: LFThemeToken) throws {
        let light = try #require(hex(of: token, in: .aqua))
        let dark = try #require(hex(of: token, in: .darkAqua))

        #expect(light != dark)
    }

    @Test("accent is the deep Clean Plate teal in light (white text passes) and the bright teal in dark")
    func accentMatchesPalette() {
        #expect(hex(of: .accent, in: .aqua) == "#178080")
        #expect(hex(of: .accent, in: .darkAqua) == "#25B1B1")
        #expect(hex(of: .accentVivid, in: .aqua) == "#25B1B1")
    }

    @Test("window chrome and text use the warm Clean Plate neutrals")
    func neutralsAreWarm() {
        #expect(hex(of: .surfaceSunken, in: .aqua) == "#F3F2F1")
        #expect(hex(of: .surfaceSunken, in: .darkAqua) == "#1C1917")
        #expect(hex(of: .border, in: .aqua) == "#CAC6C3")
        #expect(hex(of: .text, in: .aqua) == "#272321")
        #expect(hex(of: .railSelectedIcon, in: .aqua) == "#D96842")
    }

    @Test("current conflict uses Teal, not the green accent")
    func currentConflictIsTeal() {
        #expect(hex(of: .conflictCurrentHeader, in: .aqua) == "#C6EDFB")
        #expect(hex(of: .conflictCurrentHeader, in: .darkAqua) == "#164555")
    }

    @Test("teal is the default accent and uses the base color sets")
    func tealIsTheDefault() {
        #expect(AccentSetting.choice(storedValue: nil) == .teal)
        #expect(AccentSetting.choice(storedValue: "nonsense") == .teal)
        #expect(AccentSetting.choice(storedValue: "green") == .green)
        #expect(LFThemeToken.accent.assetName(for: .teal) == "lfAccent")
        #expect(LFAccentChoice.allCases.first == .teal)
    }

    @Test("only accent tokens change with the choice")
    func onlyAccentTokensChange() {
        #expect(LFThemeToken.accent.assetName(for: .blue) == "lfAccentBlue")
        #expect(LFThemeToken.accent.assetName(for: .green) == "lfAccentGreen")
        #expect(LFThemeToken.accentVivid.assetName(for: .purple) == "lfAccentVividPurple")
        #expect(LFThemeToken.accentSubtle.assetName(for: .orange) == "lfAccentSubtleOrange")
        #expect(LFThemeToken.text.assetName(for: .blue) == "lfText")
        #expect(LFThemeToken.onAccent.assetName(for: .purple) == "lfOnAccent")
    }

    @Test("every accent choice has a color set for every accent token, differing from teal", arguments: LFAccentChoice.allCases)
    func choiceHasColors(choice: LFAccentChoice) throws {
        for token in LFAccentChoice.overriddenTokens {
            let name = token.assetName(for: choice)
            #expect(NSColor(named: name) != nil, "missing \(name)")
            if choice != .teal {
                #expect(hex(named: name, in: .aqua) != hex(named: token.assetName(for: .teal), in: .aqua), "\(name) equals teal")
            }
        }
    }

    private func hex(named name: String, in appearanceName: NSAppearance.Name) -> String? {
        guard let appearance = NSAppearance(named: appearanceName), let color = NSColor(named: name) else { return nil }
        var result: String?
        appearance.performAsCurrentDrawingAppearance {
            guard let srgb = color.usingColorSpace(.sRGB) else { return }
            result = String(format: "#%02X%02X%02X", Int((srgb.redComponent * 255).rounded()),
                            Int((srgb.greenComponent * 255).rounded()), Int((srgb.blueComponent * 255).rounded()))
        }
        return result
    }

    private func hex(of token: LFThemeToken, in appearanceName: NSAppearance.Name) -> String? {
        guard let appearance = NSAppearance(named: appearanceName),
              let color = NSColor(named: token.rawValue) else { return nil }
        var result: String?
        appearance.performAsCurrentDrawingAppearance {
            guard let srgb = color.usingColorSpace(.sRGB) else { return }
            result = String(
                format: "#%02X%02X%02X",
                Int((srgb.redComponent * 255).rounded()),
                Int((srgb.greenComponent * 255).rounded()),
                Int((srgb.blueComponent * 255).rounded())
            )
        }
        return result
    }
}

@MainActor
@Suite("Appearance setting")
struct AppearanceSettingTests {
    @Test("system follows macOS, light and dark force an appearance")
    func mapsToNSAppearance() {
        #expect(AppearanceSetting.system.nsAppearanceName == nil)
        #expect(AppearanceSetting.light.nsAppearanceName == .aqua)
        #expect(AppearanceSetting.dark.nsAppearanceName == .darkAqua)
    }

    @Test("stored values round-trip", arguments: AppearanceSetting.allCases)
    func storedValueRoundTrips(setting: AppearanceSetting) {
        #expect(AppearanceSetting(storedValue: setting.rawValue) == setting)
    }

    @Test("unknown or missing stored values fall back to system", arguments: ["", "sepia", "DARK"])
    func unknownStoredValueFallsBack(raw: String) {
        #expect(AppearanceSetting(storedValue: raw) == .system)
    }
}
