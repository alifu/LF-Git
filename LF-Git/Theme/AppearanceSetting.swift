import AppKit

/// The user's appearance choice. `system` follows macOS light/dark mode.
enum AppearanceSetting: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    /// Unknown or missing stored values fall back to `system`.
    init(storedValue: String) {
        self = AppearanceSetting(rawValue: storedValue) ?? .system
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` lets the app inherit the system appearance.
    var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    /// Applies to every window, so SwiftUI and AppKit views switch together.
    func apply(to application: NSApplication = .shared) {
        application.appearance = nsAppearanceName.flatMap(NSAppearance.init(named:))
    }
}
