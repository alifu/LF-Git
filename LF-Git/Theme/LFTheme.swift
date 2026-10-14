import AppKit
import SwiftUI

// Views use semantic tokens only — never raw colors. Hex values live in Design/theme.json.

/// Which accent color the user picked in Settings > Theme. Green is the default.
enum AccentSetting {
    static let storageKey = "accentColor"

    /// Unknown or missing stored values fall back to green.
    static func choice(storedValue: String?) -> LFAccentChoice {
        storedValue.flatMap(LFAccentChoice.init(rawValue:)) ?? .green
    }

    static var current: LFAccentChoice {
        choice(storedValue: UserDefaults.standard.string(forKey: storageKey))
    }
}

extension LFThemeToken {
    /// The color set to read: the base one, or the picked accent's version of an accent token.
    func assetName(for choice: LFAccentChoice = AccentSetting.current) -> String {
        LFAccentChoice.overriddenTokens.contains(self) ? rawValue + choice.assetSuffix : rawValue
    }
}

extension Color {
    init(theme token: LFThemeToken) {
        self.init(token.assetName(), bundle: .main)
    }
}

extension NSColor {
    /// Resolves at draw time, so AppKit views follow light/dark changes automatically.
    static func theme(_ token: LFThemeToken) -> NSColor {
        guard let color = NSColor(named: token.assetName(), bundle: .main) else {
            assertionFailure("Missing color set \(token.assetName()); run LFCore/Scripts/gen_theme.py")
            return .magenta
        }
        return color
    }
}

extension ShapeStyle where Self == Color {
    static func theme(_ token: LFThemeToken) -> Color { Color(theme: token) }
}
