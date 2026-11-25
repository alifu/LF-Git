import Foundation

/// Which branches the three-column Branches list shows (All / Local / Remote).
nonisolated enum BranchScope: String, CaseIterable, Identifiable, Sendable {
    case all, local, remote

    var id: String { rawValue }

    /// Reads a stored value; anything unknown is All.
    init(stored: String?) {
        self = stored.flatMap(BranchScope.init(rawValue:)) ?? .all
    }

    var title: String {
        switch self {
        case .all: "All"
        case .local: "Local"
        case .remote: "Remote"
        }
    }

    var showsLocal: Bool { self != .remote }
    var showsRemote: Bool { self != .local }
}

/// The pinned "current target" row: the checked-out branch, what it tracks and how far apart they are.
nonisolated struct CurrentTarget: Equatable, Sendable {
    let branch: String?
    let upstream: String?
    let ahead: Int
    let behind: Int
    let isDetached: Bool

    var title: String { isDetached ? "Detached HEAD" : (branch ?? "No branch yet") }
    var detail: String { upstream.map { "tracks \($0)" } ?? "no upstream" }
    var isInSync: Bool { ahead == 0 && behind == 0 }
}

/// The Reflog as a timeline: entries by day, and which one is the current HEAD (the newest).
nonisolated struct ReflogTimeline<Item> {
    let groups: [DayGroup<Item>]
    let currentID: String?

    /// One pass: O(m) for m entries.
    init(_ items: [Item], id: (Item) -> String, date: (Item) -> Date, calendar: Calendar = .current, now: Date = Date()) {
        groups = DayGrouping.group(items, calendar: calendar, now: now, date: date)
        currentID = items.first.map(id)
    }
}

/// The toolbar branch menu's lists: local and remote are filtered by their own search box.
nonisolated enum BranchMenuFilter {
    /// Items whose name contains `query` (case-insensitive); a blank query keeps them all.
    static func matching<Item>(_ items: [Item], query: String, name: KeyPath<Item, String>) -> [Item] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? items : items.filter { $0[keyPath: name].localizedCaseInsensitiveContains(text) }
    }

    /// What Return switches to: the first match that is not already checked out.
    static func firstSwitchable<Item>(_ items: [Item], query: String, name: KeyPath<Item, String>,
                                      isCurrent: KeyPath<Item, Bool>) -> Item? {
        matching(items, query: query, name: name).first { !$0[keyPath: isCurrent] }
    }
}
