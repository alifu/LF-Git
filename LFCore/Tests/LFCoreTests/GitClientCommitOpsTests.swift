import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git client: commit operations")
struct GitClientCommitOpsTests {
    /// Five commits, each adding its own file: one…five.
    private func linearHistory() throws -> (GitFixture, GitClient, [GitCommit]) {
        let fixture = try GitFixture()
        for name in ["one", "two", "three", "four", "five"] {
            try fixture.commit("\(name).txt", "\(name)\n", message: name)
        }
        let client = GitClient(directory: fixture.directory)
        return (fixture, client, try client.log())
    }

    private func subjects(_ client: GitClient) throws -> [String] {
        try client.log().map(\.subject)
    }

    private func commit(_ subject: String, in commits: [GitCommit]) throws -> GitCommit {
        try #require(commits.first { $0.subject == subject })
    }

    @Test("a commit can be reworded in the middle of history")
    func reword() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }

        try client.rewordCommit(try commit("three", in: commits), message: "THREE\n\nwith a body")

        #expect(try subjects(client) == ["five", "four", "THREE", "two", "one"])
        #expect(try fixture.git.run(["log", "-1", "--format=%b", "HEAD~2"]).text == "with a body")
    }

    @Test("HEAD and the root commit can be reworded")
    func rewordEnds() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }

        try client.rewordCommit(try commit("five", in: commits), message: "FIVE")
        try client.rewordCommit(try commit("one", in: commits), message: "ONE")

        #expect(try subjects(client) == ["FIVE", "four", "three", "two", "ONE"])
    }

    @Test("local edits survive a rewrite of older commits")
    func keepsLocalEdits() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }
        fixture.sandbox.write("five.txt", "edited\n")
        fixture.sandbox.write("untracked.txt", "u\n")

        try client.rewordCommit(try commit("two", in: commits), message: "TWO")

        #expect(fixture.read("five.txt") == "edited\n")
        #expect(fixture.read("untracked.txt") == "u\n")
        #expect(try subjects(client) == ["five", "four", "three", "TWO", "one"])
    }

    @Test("a commit is dropped")
    func drop() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }

        try client.dropCommit(try commit("three", in: commits))

        #expect(try subjects(client) == ["five", "four", "two", "one"])
        #expect(!FileManager.default.fileExists(atPath: fixture.sandbox.path("three.txt")))
    }

    @Test("squash folds a commit into the one before it and keeps both messages; fixup keeps one")
    func squashAndFixup() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }

        try client.squashCommit(try commit("four", in: commits))
        #expect(try subjects(client).count == 4)
        #expect(try fixture.git.run(["log", "-1", "--format=%B", "HEAD~1"]).text.contains("three"))
        #expect(try fixture.git.run(["log", "-1", "--format=%B", "HEAD~1"]).text.contains("four"))

        let now = try client.log()
        try client.fixupCommit(try #require(now.first { $0.subject == "two" }))
        #expect(try subjects(client) == ["five", "three", "one"])
        #expect(fixture.read("two.txt") == "two\n")
    }

    @Test("a commit moves up and down")
    func move() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }

        try client.moveCommitUp(try commit("two", in: commits))
        #expect(try subjects(client) == ["five", "four", "two", "three", "one"])

        let now = try client.log()
        try client.moveCommitDown(try #require(now.first { $0.subject == "four" }))
        #expect(try subjects(client) == ["five", "two", "four", "three", "one"])
    }

    @Test("the newest commit cannot move up and the oldest cannot move down")
    func moveLimits() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }

        #expect(throws: GitClientError.self) { try client.moveCommitUp(try commit("five", in: commits)) }
        #expect(throws: GitClientError.self) { try client.moveCommitDown(try commit("one", in: commits)) }
    }

    @Test("edit stops the rebase at the commit so it can be changed, then continues")
    func edit() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }

        try client.editCommit(try commit("three", in: commits))

        #expect(try client.operation() == .rebase)
        fixture.sandbox.write("extra.txt", "extra\n")
        try client.stage(["extra.txt"])
        try client.commit(message: "three, edited", amend: true)
        try client.continueOperation(.rebase)
        #expect(try client.operation() == nil)
        #expect(try subjects(client) == ["five", "four", "three, edited", "two", "one"])
    }

    @Test("history that contains merges is not rewritten")
    func refusesMerges() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "base")
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("topic")
        try fixture.commit("b.txt", "t\n", message: "topic")
        try client.switchBranch("main")
        try fixture.commit("c.txt", "m\n", message: "main")
        try client.mergeBranch("topic", mode: .noFastForward)
        try fixture.commit("d.txt", "d\n", message: "after")
        let base = try #require(try client.log().first { $0.subject == "base" })

        #expect(throws: GitClientError.self) { try client.dropCommit(base) }
    }

    @Test("staged changes are folded into an older commit")
    func amendOlder() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }
        fixture.sandbox.write("two.txt", "two, fixed\n")
        try client.stage(["two.txt"])

        try client.amendCommit(try commit("two", in: commits))

        #expect(try subjects(client) == ["five", "four", "three", "two", "one"])
        #expect(try fixture.git.run(["show", "HEAD~3:two.txt"]).text == "two, fixed")
        #expect(try client.status().isClean)
    }

    @Test("fixup commits above a commit are squashed automatically")
    func autosquash() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }
        fixture.sandbox.write("two.txt", "fixed 1\n")
        try client.stage(["two.txt"])
        try client.createFixupCommit(for: try commit("two", in: commits))

        try client.autosquash(above: try commit("one", in: commits))

        #expect(try subjects(client) == ["five", "four", "three", "two", "one"])
        #expect(try fixture.git.run(["show", "HEAD~3:two.txt"]).text == "fixed 1")
    }

    @Test("revert adds a commit that undoes another")
    func revert() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }

        try client.revert(try commit("three", in: commits))

        #expect(try client.log().first?.subject == "Revert \"three\"")
        #expect(!FileManager.default.fileExists(atPath: fixture.sandbox.path("three.txt")))
    }

    @Test("cherry-pick copies commits onto another branch, oldest first")
    func cherryPick() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }
        try client.switchBranch("main")
        try fixture.git.run(["checkout", "-q", "-b", "target", try commit("one", in: commits).hash])

        try client.cherryPick([try commit("three", in: commits), try commit("four", in: commits)])

        #expect(try subjects(client) == ["four", "three", "one"])
    }

    @Test("a cherry-pick that conflicts leaves the operation to resolve")
    func cherryPickConflict() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("c.txt")])
        try fixture.git.run(["merge", "--abort"])
        let client = GitClient(directory: fixture.directory)
        let theirs = try #require(try client.log(allBranches: true).first { $0.subject == "theirs" })

        #expect(throws: GitError.self) { try client.cherryPick([theirs]) }

        #expect(try client.operation() == .cherryPick)
    }

    @Test("checking out a commit detaches HEAD; a branch and a tag can start there")
    func detached() throws {
        let (fixture, client, commits) = try linearHistory()
        defer { withExtendedLifetime(fixture) {} }
        let two = try commit("two", in: commits)

        try client.checkoutDetached(two)
        #expect(try client.status().branch == nil)

        try client.createBranch("from-two", from: two.hash)
        try client.createTag("t2", at: two.hash)
        #expect(try fixture.git.run(["rev-parse", "from-two"]).text == two.hash)
        #expect(try client.tags().first?.commit == two.hash)
    }

    @Test("commit without hooks skips a failing pre-commit hook")
    func noVerify() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let hook = fixture.sandbox.path(".git/hooks/pre-commit")
        fixture.sandbox.write(".git/hooks/pre-commit", "#!/bin/sh\nexit 1\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook)
        fixture.sandbox.write("a.txt", "2\n")
        let client = GitClient(directory: fixture.directory)
        try client.stage(["a.txt"])

        #expect(throws: GitError.self) { try client.commit(message: "blocked") }
        try client.commit(message: "forced", noVerify: true)

        #expect(try client.log().first?.subject == "forced")
    }

    @Test("amending keeps the message when asked to")
    func amendKeepingMessage() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "keep me")
        fixture.sandbox.write("b.txt", "2\n")
        let client = GitClient(directory: fixture.directory)
        try client.stage(["b.txt"])

        try client.amendKeepingMessage()

        #expect(try client.log().map(\.subject) == ["keep me"])
        #expect(try fixture.git.run(["show", "--name-only", "--format=", "HEAD"]).text.contains("b.txt"))
    }

    @Test("undo walks HEAD back one step (commits, checkouts) and the same call redoes it")
    func undoRedo() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        try fixture.commit("a.txt", "2\n", message: "two")
        let client = GitClient(directory: fixture.directory)

        let undone = try client.restorePreviousHead()
        #expect(undone.hasPrefix("commit"))
        #expect(try client.log().map(\.subject) == ["one"])

        _ = try client.restorePreviousHead() // the redo of the undo
        #expect(try client.log().map(\.subject) == ["two", "one"])

        try client.createBranch("topic")
        _ = try client.restorePreviousHead()
        #expect(try fixture.git.run(["branch", "--show-current"]).text == "main")
    }

    @Test("undo refuses to throw away local edits")
    func undoKeepsEdits() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        try fixture.commit("a.txt", "2\n", message: "two")
        fixture.sandbox.write("a.txt", "3\n")
        let client = GitClient(directory: fixture.directory)

        #expect(throws: GitError.self) { try client.restorePreviousHead() }
        #expect(fixture.read("a.txt") == "3\n")
    }

    @Test("nuking the work tree removes edits and untracked files")
    func nuke() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("a.txt", "dirty\n")
        fixture.sandbox.write("junk.txt", "junk\n")
        let client = GitClient(directory: fixture.directory)

        try client.discardEverything()

        #expect(try client.status().isClean)
        #expect(fixture.read("a.txt") == "1\n")
    }
}

@Suite("Git client: ordering commits for a cherry-pick")
struct CommitOrderingTests {
    @Test("an ancestor comes before its descendants whatever the copy order or timestamps")
    func ordering() throws {
        let fixture = try GitFixture()
        for name in ["a", "b", "c"] { try fixture.commit("\(name).txt", "\(name)\n", message: name) }
        let client = GitClient(directory: fixture.directory)
        let log = try client.log() // c, b, a — all within the same second

        let sorted = try client.sortedOldestFirst(log)

        #expect(sorted.map(\.subject) == ["a", "b", "c"])
        #expect(try client.sortedOldestFirst([log[1], log[2], log[0]]).map(\.subject) == ["a", "b", "c"])
    }
}
