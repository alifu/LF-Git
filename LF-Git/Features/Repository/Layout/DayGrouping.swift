import Foundation

/// Entries of one day, for a list with day headers ("Today", "Yesterday", "3 Nov 2026").
nonisolated struct DayGroup<Item>: Identifiable {
    /// Unique within one grouping, even when a day appears twice (the list is not sorted by date).
    let id: Int
    let title: String
    let items: [Item]
}

extension DayGroup: Sendable where Item: Sendable {}

nonisolated enum DayGrouping {
    /// Groups runs of entries that fall on the same day, keeping list order. One pass: O(m) for m entries.
    /// The list is not re-sorted, so a day that comes back after another day starts a new group.
    static func group<Item>(_ items: [Item], calendar: Calendar = .current, now: Date = Date(),
                            date: (Item) -> Date) -> [DayGroup<Item>] {
        var groups: [DayGroup<Item>] = []
        var run: [Item] = []
        var runDay: Date?

        func close() {
            guard let day = runDay, !run.isEmpty else { return }
            groups.append(DayGroup(id: groups.count, title: title(of: day, calendar: calendar, now: now), items: run))
        }

        for item in items {
            let day = calendar.startOfDay(for: date(item))
            if day != runDay {
                close()
                run = []
                runDay = day
            }
            run.append(item)
        }
        close()
        return groups
    }

    static func title(of day: Date, calendar: Calendar, now: Date) -> String {
        let today = calendar.startOfDay(for: now)
        if day == today { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday { return "Yesterday" }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return day.formatted(style)
    }
}
