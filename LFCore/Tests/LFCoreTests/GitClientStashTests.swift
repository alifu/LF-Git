import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git client: stash")
struct GitClientStashTests {
    private func fixtureWithEdits() throws -> (GitFixture, GitClient) {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        try fixture.commit("b.txt", "1\n")
        fixture.sandbox.write("a.txt", "changed a\n")
        return (fixture, GitClient(directory: fixture.directory))
    }

    @Test("stashing saves the edits and cleans the work tree")
    func push() throws {
        let (fixture, client) = try fixtureWithEdits()

        try client.stashPush(message: "wip a")

        #expect(fixture.read("a.txt") == "1\n")
        let stashes = try client.stashes()
        #expect(stashes.count == 1)
        #expect(stashes[0].message == "wip a")
        #expect(stashes[0].ref == "stash@{0}")
        #expect(stashes[0].branch == "main")
    }

    @Test("untracked files are stashed only when asked for")
    func untracked() throws {
        let (fixture, client) = try fixtureWithEdits()
        fixture.sandbox.write("new.txt", "new\n")

        try client.stashPush(message: "tracked only")
        #expect(FileManager.default.fileExists(atPath: fixture.sandbox.path("new.txt")))

        fixture.sandbox.write("a.txt", "again\n")
        try client.stashPush(message: "everything", includeUntracked: true)
        #expect(!FileManager.default.fileExists(atPath: fixture.sandbox.path("new.txt")))
        #expect(try client.stashes().count == 2)
    }

    @Test("only the staged changes can be stashed")
    func stagedOnly() throws {
        let (fixture, client) = try fixtureWithEdits()
        fixture.sandbox.write("b.txt", "changed b\n")
        try client.stage(["a.txt"])

        try client.stashPush(message: "staged", stagedOnly: true)

        #expect(fixture.read("a.txt") == "1\n")
        #expect(fixture.read("b.txt") == "changed b\n")
    }

    @Test("keep-index stashes everything but leaves staged changes in place")
    func keepIndex() throws {
        let (fixture, client) = try fixtureWithEdits()
        try client.stage(["a.txt"])

        try client.stashPush(message: "keep", keepIndex: true)

        #expect(fixture.read("a.txt") == "changed a\n")
        #expect(try client.stashes().count == 1)
    }

    @Test("pop restores the edits and drops the stash; apply keeps it")
    func applyAndPop() throws {
        let (fixture, client) = try fixtureWithEdits()
        try client.stashPush(message: "wip")
        let stash = try #require(try client.stashes().first)

        try client.stashApply(stash)
        #expect(fixture.read("a.txt") == "changed a\n")
        #expect(try client.stashes().count == 1)

        try client.discard(try client.status().unstaged)
        try client.stashPop(stash)
        #expect(fixture.read("a.txt") == "changed a\n")
        #expect(try client.stashes().isEmpty)
    }

    @Test("dropping removes only the chosen stash")
    func drop() throws {
        let (fixture, client) = try fixtureWithEdits()
        try client.stashPush(message: "first")
        fixture.sandbox.write("a.txt", "second edit\n")
        try client.stashPush(message: "second")
        let first = try #require(try client.stashes().first { $0.message == "first" })

        try client.stashDrop(first)

        #expect(try client.stashes().map(\.message) == ["second"])
    }

    @Test("a stash can be renamed")
    func rename() throws {
        let (fixture, client) = try fixtureWithEdits()
        defer { withExtendedLifetime(fixture) {} }
        try client.stashPush(message: "old")
        let stash = try #require(try client.stashes().first)

        try client.stashRename(stash, to: "better name")

        #expect(try client.stashes().map(\.message) == ["better name"])
    }

    @Test("a stash becomes a branch")
    func branch() throws {
        let (fixture, client) = try fixtureWithEdits()
        try client.stashPush(message: "wip")
        let stash = try #require(try client.stashes().first)

        try client.stashBranch("from-stash", from: stash)

        #expect(try fixture.git.run(["branch", "--show-current"]).text == "from-stash")
        #expect(fixture.read("a.txt") == "changed a\n")
        #expect(try client.stashes().isEmpty)
    }

    @Test("the files of a stash are listed and diffable")
    func files() throws {
        let (fixture, client) = try fixtureWithEdits()
        defer { withExtendedLifetime(fixture) {} }
        try client.stashPush(message: "wip")
        let stash = try #require(try client.stashes().first)

        let files = try client.changedFiles(in: stash.commit)
        #expect(files.map(\.path) == ["a.txt"])
        let diff = try client.diff(of: .commit(stash.commit, path: "a.txt"))
        #expect(diff.index.hunks.count == 1)
    }

    @Test("nothing to stash is a clear error, and option-like messages stay messages")
    func errors() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)

        #expect(throws: GitClientError.nothingToStash) { try client.stashPush(message: "x") }

        fixture.sandbox.write("a.txt", "2\n")
        try client.stashPush(message: "--include-untracked")
        #expect(try client.stashes().first?.message == "--include-untracked")
    }
}
