import Foundation
import LFKit
import LFTestSupport
import Testing
@testable import LF_Git

@Suite("Dashboard repository summaries")
struct RepositorySummaryTests {
    private func nul(_ fields: [String]) -> Data { Data((fields.joined(separator: "\0") + "\0").utf8) }

    @Test("status output is counted into branch, changes, conflicts and distance from upstream")
    func parse() {
        let output = nul([
            "# branch.oid abc", "# branch.head feature/x", "# branch.upstream origin/feature/x", "# branch.ab +2 -1",
            "1 .M N... 100644 100644 100644 a b src/a.swift", "? new.txt",
            "2 R. N... 100644 100644 100644 a b R100 renamed.txt", "old.txt",
            "u UU N... 100644 100644 100644 100644 a b c conflicted.txt",
        ])

        let summary = RepositorySummary.parse(output)

        #expect(summary.branch == "feature/x")
        #expect(summary.changeCount == 3)
        #expect(summary.conflictCount == 1)
        #expect(summary.ahead == 2)
        #expect(summary.behind == 1)
        #expect(summary.needsAttention)
    }

    @Test("a detached HEAD has no branch name")
    func detached() {
        #expect(RepositorySummary.parse(nul(["# branch.head (detached)"])).branch == nil)
    }

    @Test("a hundred thousand changes are counted, not listed")
    func manyChanges() {
        let output = nul((0..<100_000).map { "? build/file\($0).o" })
        let started = ContinuousClock.now

        let summary = RepositorySummary.parse(output)

        #expect(summary.changeCount == 100_000)
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test("a repository is read from disk, and a missing folder is reported as missing")
    func load() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        try Data("2\n".utf8).write(to: fixture.directory.appendingPathComponent("b.txt"))

        let summary = RepositorySummary.load(path: fixture.path)

        #expect(summary.branch == "main")
        #expect(summary.changeCount == 1)
        #expect(!summary.needsAttention)
        #expect(RepositorySummary.load(path: "/nonexistent/lfgit/none") == .missing)
    }

    @Test("an unfinished merge needs attention")
    func conflicted() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("c.txt")])

        let summary = RepositorySummary.load(path: fixture.path)

        #expect(summary.conflictCount == 1)
        #expect(summary.hasUnfinishedOperation)
        #expect(summary.needsAttention)
    }

    @MainActor
    @Test("every repository gets a summary")
    func refreshAll() async throws {
        let first = try GitFixture()
        try first.commit("a.txt", "1\n")
        let second = try GitFixture()
        try second.commit("b.txt", "1\n")
        let summaries = RepositorySummaries()

        await summaries.refresh([first.path, second.path, "/nonexistent/lfgit/none"])

        #expect(summaries.summary(for: first.path)?.branch == "main")
        #expect(summaries.summary(for: second.path)?.branch == "main")
        #expect(summaries.summary(for: "/nonexistent/lfgit/none")?.isMissing == true)
    }
}
