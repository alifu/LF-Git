import Testing
@testable import LF_Git

@Suite("Branch menu filter")
struct BranchMenuFilterTests {
    private struct Branch: Equatable {
        let name: String
        var isCurrent = false
    }

    private static let locals = [Branch(name: "main", isCurrent: true), Branch(name: "feature/menu"), Branch(name: "release")]

    private static func matching(_ items: [Branch], _ query: String) -> [String] {
        BranchMenuFilter.matching(items, query: query, name: \.name).map(\.name)
    }

    private static func firstSwitchable(_ query: String) -> String? {
        BranchMenuFilter.firstSwitchable(locals, query: query, name: \.name, isCurrent: \.isCurrent)?.name
    }

    @Test("A blank query keeps every branch")
    func blankQueryKeepsAll() {
        #expect(Self.matching(Self.locals, "  ") == ["main", "feature/menu", "release"])
    }

    @Test("A query matches names case-insensitively")
    func queryMatchesCaseInsensitively() {
        #expect(Self.matching(Self.locals, "MENU") == ["feature/menu"])
    }

    @Test("Return skips the checked-out branch")
    func firstSwitchableSkipsCurrent() {
        #expect(Self.firstSwitchable("") == "feature/menu")
        #expect(Self.firstSwitchable("main") == nil)
    }

    @Test("Return has nothing to switch to when nothing matches")
    func firstSwitchableNoMatch() {
        #expect(Self.firstSwitchable("nope") == nil)
    }
}
