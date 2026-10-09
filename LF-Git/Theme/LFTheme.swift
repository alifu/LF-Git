import AppKit
import SwiftUI

// Views use semantic tokens only — never raw colors. Hex values live in Design/theme.json.

extension Color {
    init(theme token: LFThemeToken) {
        self.init(token.rawValue, bundle: .main)
    }
}

extension NSColor {
    /// Resolves at draw time, so AppKit views follow light/dark changes automatically.
    static func theme(_ token: LFThemeToken) -> NSColor {
        guard let color = NSColor(named: token.rawValue, bundle: .main) else {
            assertionFailure("Missing color set \(token.rawValue); run LFCore/Scripts/gen_theme.py")
            return .magenta
        }
        return color
    }
}

extension ShapeStyle where Self == Color {
    static func theme(_ token: LFThemeToken) -> Color { Color(theme: token) }
}
