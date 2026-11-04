import Foundation
import Testing
@testable import LF_Git

@Suite("Lists layout")
struct ListsLayoutTests {
    private struct Item: Equatable, Sendable {
        let id: String
        let date: Date
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func item(_ id: String, daysAgo: Int = 0) -> Item {
        Item(id: id, date: now.addingTimeInterval(TimeInterval(-daysAgo * 86_400)))
    }

    // MARK: Branch scope

    @Test("All shows local and remote branches")
    func allScope() {
        #expect(BranchScope.all.showsLocal)
        #expect(BranchScope.all.showsRemote)
    }

    @Test("Local hides the remote branches and Remote hides the local ones")
    func singleScopes() {
        #expect(BranchScope.local.showsLocal)
        #expect(!BranchScope.local.showsRemote)
        #expect(!BranchScope.remote.showsLocal)
        #expect(BranchScope.remote.showsRemote)
    }

    @Test("a stored scope that is unknown falls back to All")
    func storedScope() {
        #expect(BranchScope(stored: "remote") == .remote)
        #expect(BranchScope(stored: "bogus") == .all)
        #expect(BranchScope(stored: nil) == .all)
    }

    // MARK: Current target

    @Test("the target says what the branch tracks and how far apart they are")
    func targetSummary() {
        let target = CurrentTarget(branch: "main", upstream: "origin/main", ahead: 2, behind: 1, isDetached: false)

        #expect(target.title == "main")
        #expect(target.detail == "tracks origin/main")
        #expect(!target.isInSync)
    }

    @Test("a branch without an upstream says so and is not out of sync")
    func targetWithoutUpstream() {
        let target = CurrentTarget(branch: "topic", upstream: nil, ahead: 0, behind: 0, isDetached: false)

        #expect(target.detail == "no upstream")
        #expect(target.isInSync)
    }

    @Test("a detached HEAD is titled as such")
    func detachedTarget() {
        let target = CurrentTarget(branch: nil, upstream: nil, ahead: 0, behind: 0, isDetached: true)

        #expect(target.title == "Detached HEAD")
    }

    // MARK: Reflog timeline

    @Test("the newest reflog entry is the current one")
    func currentEntry() {
        let items = [Self.item("HEAD@{0}"), Self.item("HEAD@{1}"), Self.item("HEAD@{2}", daysAgo: 3)]
        let timeline = ReflogTimeline(items, id: \.id, date: \.date, calendar: Self.calendar, now: Self.now)

        #expect(timeline.currentID == "HEAD@{0}")
        #expect(timeline.groups.count == 2)
        #expect(timeline.groups[0].items.count == 2)
    }

    @Test("an empty reflog has no current entry")
    func noCurrentEntry() {
        let timeline = ReflogTimeline([Item](), id: \.id, date: \.date, calendar: Self.calendar, now: Self.now)

        #expect(timeline.currentID == nil)
        #expect(timeline.groups.isEmpty)
    }
}
