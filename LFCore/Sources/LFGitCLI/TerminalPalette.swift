import Foundation

/// 24-bit terminal colours taken from the app theme (Design/theme.json, Atlassian palette).
/// A test keeps every entry in sync with theme.json.
public struct TerminalPalette: Sendable, Equatable {
    public struct RGB: Sendable, Equatable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        init(hex: String) {
            let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            let value = UInt32(digits, radix: 16) ?? 0
            red = UInt8((value >> 16) & 0xFF)
            green = UInt8((value >> 8) & 0xFF)
            blue = UInt8(value & 0xFF)
        }
    }

    struct Entry {
        let role: String
        let token: String
        let light: String
        let dark: String
    }

    /// Role -> theme token and its resolved light/dark hex values.
    static let entries: [Entry] = [
        Entry(role: "current", token: "minimapCurrent", light: "#2898BD", dark: "#42B2D7"),
        Entry(role: "incoming", token: "minimapIncoming", light: "#357DE8", dark: "#4688EC"),
        Entry(role: "base", token: "syntaxKeyword", light: "#964AC0", dark: "#D8A0F7"),
        Entry(role: "danger", token: "danger", light: "#C9372C", dark: "#F87168"),
        Entry(role: "accent", token: "accent", light: "#1F845A", dark: "#4BCE97"),
        Entry(role: "muted", token: "textSubtle", light: "#6B6E76", dark: "#96999E"),
    ]

    public let current: RGB
    public let incoming: RGB
    public let base: RGB
    public let danger: RGB
    public let accent: RGB
    public let muted: RGB

    private init(dark: Bool) {
        func color(_ role: String) -> RGB {
            guard let entry = Self.entries.first(where: { $0.role == role }) else {
                preconditionFailure("missing terminal colour role \(role)")
            }
            return RGB(hex: dark ? entry.dark : entry.light)
        }
        current = color("current")
        incoming = color("incoming")
        base = color("base")
        danger = color("danger")
        accent = color("accent")
        muted = color("muted")
    }

    public static let dark = TerminalPalette(dark: true)
    public static let light = TerminalPalette(dark: false)

    /// Honours NO_COLOR, dumb terminals and pipes; picks light or dark from COLORFGBG, dark by default.
    public static func detect(environment: [String: String], isTerminal: Bool) -> TerminalPalette? {
        guard isTerminal, environment["NO_COLOR"] == nil, environment["TERM"] != "dumb" else {
            return nil
        }
        // COLORFGBG is "foreground;background" (ANSI indexes); 7 and 15 are the light backgrounds.
        if let background = environment["COLORFGBG"]?.split(separator: ";").last.flatMap({ Int($0) }),
           background == 7 || background == 15 {
            return .light
        }
        return .dark
    }

    public func paint(_ text: String, _ color: RGB, bold: Bool = false) -> String {
        let weight = bold ? "\u{1B}[1m" : ""
        return "\(weight)\u{1B}[38;2;\(color.red);\(color.green);\(color.blue)m\(text)\u{1B}[0m"
    }
}
