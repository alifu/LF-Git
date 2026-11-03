import Foundation
import Testing
@testable import LF_Git

@MainActor
@Suite("Side menu")
struct SideMenuTests {
    @Test("Changes, Branches and History lead; the other sections follow below")
    func groups() {
        let menu = SideMenuSections(hasConflicts: false, selected: .changes)

        #expect(menu.primary == [.changes, .branches, .history])
        #expect(menu.more == [.stash, .tags, .remotes, .reflog, .worktrees, .submodules])
    }

    @Test("every section except Conflicts is always listed exactly once")
    func everySectionListedOnce() {
        let menu = SideMenuSections(hasConflicts: true, selected: .changes)
        let listed = menu.primary + menu.more

        #expect(Set(listed).count == listed.count)
        #expect(Set(listed) == Set(RepositorySection.allCases))
    }

    @Test("Conflicts is hidden while nothing is conflicted")
    func conflictsHiddenWithoutConflicts() {
        let menu = SideMenuSections(hasConflicts: false, selected: .history)

        #expect(!menu.more.contains(.conflicts))
    }

    @Test("Conflicts shows at the end while files are conflicted")
    func conflictsShownWithConflicts() {
        let menu = SideMenuSections(hasConflicts: true, selected: .history)

        #expect(menu.more.last == .conflicts)
    }

    @Test("Conflicts stays while selected, so resolving the last file does not pull the section away")
    func conflictsStaysWhileSelected() {
        let menu = SideMenuSections(hasConflicts: false, selected: .conflicts)

        #expect(menu.more.last == .conflicts)
    }
}

@MainActor
@Suite("Top bar")
struct TopBarTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("a repository that never fetched says so")
    func neverFetched() {
        #expect(RemoteButtons.fetchedText(nil, now: now) == "Never fetched")
    }

    @Test("a fetch in the last minute reads as just now")
    func justNow() {
        #expect(RemoteButtons.fetchedText(now.addingTimeInterval(-20), now: now) == "Just now")
    }

    @Test("older fetches read as a relative time")
    func relative() {
        let text = RemoteButtons.fetchedText(now.addingTimeInterval(-5 * 60), now: now)

        #expect(text.contains("5"))
        #expect(text != "Just now")
    }
}
