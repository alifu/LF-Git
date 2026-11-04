import Foundation
import Testing
@testable import LF_Git

@Suite("Day grouping")
struct DayGroupingTests {
    private struct Entry: Equatable {
        let name: String
        let date: Date
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11-04 15:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_804_400)

    private func hoursAgo(_ hours: Double, _ name: String) -> Entry {
        Entry(name: name, date: now.addingTimeInterval(-hours * 3600))
    }

    @Test("consecutive entries of the same day share one group, in order")
    func groupsByDay() {
        let entries = [hoursAgo(1, "a"), hoursAgo(2, "b"), hoursAgo(20, "c"), hoursAgo(50, "d")]

        let groups = DayGrouping.group(entries, calendar: calendar, now: now, date: \.date)

        #expect(groups.map(\.items.count) == [2, 1, 1])
        #expect(groups.flatMap(\.items).map(\.name) == ["a", "b", "c", "d"])
    }

    @Test("today and yesterday are named; older days show the date")
    func titles() {
        let entries = [hoursAgo(1, "today"), hoursAgo(20, "yesterday"), hoursAgo(80, "older")]

        let groups = DayGrouping.group(entries, calendar: calendar, now: now, date: \.date)

        #expect(groups[0].title == "Today")
        #expect(groups[1].title == "Yesterday")
        #expect(groups[2].title != "Today" && groups[2].title != "Yesterday")
        #expect(!groups[2].title.isEmpty)
    }

    @Test("the same day appearing again after another day starts a new group, so list order is kept")
    func keepsOrder() {
        let entries = [hoursAgo(1, "a"), hoursAgo(30, "b"), hoursAgo(2, "c")]

        let groups = DayGrouping.group(entries, calendar: calendar, now: now, date: \.date)

        #expect(groups.map(\.items.count) == [1, 1, 1])
    }

    @Test("group ids are unique even when a day repeats")
    func uniqueIDs() {
        let entries = [hoursAgo(1, "a"), hoursAgo(30, "b"), hoursAgo(2, "c")]

        let groups = DayGrouping.group(entries, calendar: calendar, now: now, date: \.date)

        #expect(Set(groups.map(\.id)).count == groups.count)
    }

    @Test("no entries, no groups")
    func empty() {
        #expect(DayGrouping.group([Entry](), calendar: calendar, now: now, date: \.date).isEmpty)
    }
}
