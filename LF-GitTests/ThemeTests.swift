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

    @Test("accent is Atlassian Green700 in light and Green400 in dark")
    func accentMatchesPalette() {
        #expect(hex(of: .accent, in: .aqua) == "#1F845A")
        #expect(hex(of: .accent, in: .darkAqua) == "#4BCE97")
    }

    @Test("current conflict uses Teal, not the green accent")
    func currentConflictIsTeal() {
        #expect(hex(of: .conflictCurrentHeader, in: .aqua) == "#C6EDFB")
        #expect(hex(of: .conflictCurrentHeader, in: .darkAqua) == "#164555")
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
