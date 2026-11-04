import Foundation

/// How the Changes section is laid out (Settings › Layout).
nonisolated enum ChangesLayout: String, CaseIterable, Identifiable, Sendable {
    /// L1: the file list in the sidebar card, the diff in the detail card.
    case classic
    /// L4: the diff opens inside the list card, which widens; the commit box and branch sit beside it.
    case inline
    /// L3: a lane with the staged files, the commit box and the branch's commits, on a canvas; details open beside it.
    case lanes

    static let `default` = ChangesLayout.classic

    var id: String { rawValue }

    /// Reads a stored value; anything unknown (an older or newer build wrote it) is Classic.
    init(stored: String?) {
        self = stored.flatMap(ChangesLayout.init(rawValue:)) ?? .default
    }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .inline: "Inline preview"
        case .lanes: "Lanes"
        }
    }
}

/// How Branches, History, Stash, Tags and Reflog are laid out (Settings › Layout).
nonisolated enum ListsLayout: String, CaseIterable, Identifiable, Sendable {
    /// L1: list card and detail card.
    case classic
    /// L2: list card, then one card with the commits and the preview side by side.
    case threeColumn

    static let `default` = ListsLayout.classic

    var id: String { rawValue }

    init(stored: String?) {
        self = stored.flatMap(ListsLayout.init(rawValue:)) ?? .default
    }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .threeColumn: "Three columns"
        }
    }
}

/// The `UserDefaults` keys of the layout choices, for `@AppStorage`.
nonisolated enum LayoutPreferences {
    static let changesKey = "layout.changes"
    static let listsKey = "layout.lists"
    /// L7: the Reflog as a timeline grouped by day.
    static let timelineKey = "layout.timeline"
    static let timelineDefault = false
}
