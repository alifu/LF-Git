import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git operations in progress")
struct GitOperationTests {
    @Test("no operation is in progress in a normal repository")
    func none() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")

        #expect(try GitClient(directory: fixture.directory).operation() == nil)
    }

    @Test("a conflicted merge is detected, and can be aborted")
    func mergeAbort() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        let client = GitClient(directory: fixture.directory)

        #expect(try client.operation() == .merge)
        try client.abort(.merge)

        #expect(try client.operation() == nil)
        #expect(fixture.read("a.txt") == "a\nb-ours\nc\n")
    }

    @Test("continuing a merge after resolving creates the merge commit")
    func mergeContinue() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        let client = GitClient(directory: fixture.directory)
        fixture.sandbox.write("a.txt", "a\nresolved\nc\n")
        try client.stage(["a.txt"])

        try client.continueOperation(.merge)

        #expect(try client.operation() == nil)
        let parents = try fixture.git.run(["rev-list", "--parents", "-n", "1", "HEAD"]).text.split(separator: " ")
        #expect(parents.count == 3) // the commit and its two parents
    }

    @Test("continuing with conflicts left reports an error and keeps the operation")
    func continueUnresolved() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        let client = GitClient(directory: fixture.directory)

        #expect(throws: GitError.self) { try client.continueOperation(.merge) }
        #expect(try client.operation() == .merge)
    }

    private func rebaseConflict(_ fixture: GitFixture) throws {
        try fixture.commit("a.txt", "a\nb\nc\n", message: "base")
        try fixture.git.run(["checkout", "-q", "-b", "topic"])
        try fixture.commit("a.txt", "a\nb-topic\nc\n", message: "topic change")
        try fixture.git.run(["checkout", "-q", "main"])
        try fixture.commit("a.txt", "a\nb-main\nc\n", message: "main change")
        try fixture.git.run(["checkout", "-q", "topic"])
        try fixture.git.run(["rebase", "main"], allowedStatuses: [0, 1])
    }

    @Test("a conflicted rebase is detected and can continue after the resolution")
    func rebaseContinue() throws {
        let fixture = try GitFixture()
        try rebaseConflict(fixture)
        let client = GitClient(directory: fixture.directory)
        #expect(try client.operation() == .rebase)
        fixture.sandbox.write("a.txt", "a\nresolved\nc\n")
        try client.stage(["a.txt"])

        try client.continueOperation(.rebase)

        #expect(try client.operation() == nil)
        #expect(try fixture.git.run(["log", "-1", "--format=%s"]).text == "topic change")
        #expect(fixture.read("a.txt") == "a\nresolved\nc\n")
    }

    @Test("a conflicted rebase can be aborted or have the commit skipped")
    func rebaseAbortAndSkip() throws {
        let aborting = try GitFixture()
        try rebaseConflict(aborting)
        let abortClient = GitClient(directory: aborting.directory)
        try abortClient.abort(.rebase)
        #expect(try abortClient.operation() == nil)
        #expect(aborting.read("a.txt") == "a\nb-topic\nc\n")

        let skipping = try GitFixture()
        try rebaseConflict(skipping)
        let skipClient = GitClient(directory: skipping.directory)
        try skipClient.skip(.rebase)
        #expect(try skipClient.operation() == nil)
        #expect(skipping.read("a.txt") == "a\nb-main\nc\n")
    }

    @Test("a conflicted cherry-pick is detected and can continue")
    func cherryPick() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "a\nb\nc\n", message: "base")
        try fixture.git.run(["checkout", "-q", "-b", "other"])
        let picked = try fixture.commit("a.txt", "a\nb-other\nc\n", message: "other change")
        try fixture.git.run(["checkout", "-q", "main"])
        try fixture.commit("a.txt", "a\nb-main\nc\n", message: "main change")
        try fixture.git.run(["cherry-pick", picked], allowedStatuses: [0, 1])
        let client = GitClient(directory: fixture.directory)
        #expect(try client.operation() == .cherryPick)
        fixture.sandbox.write("a.txt", "a\nboth\nc\n")
        try client.stage(["a.txt"])

        try client.continueOperation(.cherryPick)

        #expect(try client.operation() == nil)
        #expect(try fixture.git.run(["log", "-1", "--format=%s"]).text == "other change")
    }
}

@Suite("Git remotes")
struct GitRemoteTests {
    @Test("push sends new commits and pull brings them in")
    func pushAndPull() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let origin = try fixture.addOrigin()
        let other = try GitFixture(cloning: origin)
        let otherClient = GitClient(directory: other.directory)
        let client = GitClient(directory: fixture.directory)

        try other.commit("b.txt", "from other\n")
        try otherClient.push()
        try client.fetch()
        #expect(try client.status().behind == 1)
        try client.pull()

        #expect(fixture.read("b.txt") == "from other\n")
        #expect(try client.status().behind == 0)
        try fixture.commit("c.txt", "mine\n")
        try client.push()
        #expect(try client.status().ahead == 0)
        #expect(try otherClient.status().ahead == 0)
    }

    @Test("pushing a branch without an upstream sets one")
    func pushNewBranch() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        try fixture.addOrigin()
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("topic")
        try fixture.commit("b.txt", "1\n")

        try client.push()

        #expect(try client.status().upstream == "origin/topic")
    }

    @Test("pulling diverged history fails clearly and leaves the repository untouched")
    func divergedPull() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let origin = try fixture.addOrigin()
        let other = try GitFixture(cloning: origin)
        try other.commit("b.txt", "other\n")
        try GitClient(directory: other.directory).push()
        try fixture.commit("c.txt", "mine\n")
        let client = GitClient(directory: fixture.directory)
        let before = try fixture.git.run(["rev-parse", "HEAD"]).text

        #expect(throws: GitError.self) { try client.pull() }

        #expect(try fixture.git.run(["rev-parse", "HEAD"]).text == before)
        #expect(try client.operation() == nil)
    }

    @Test("a repository without a remote reports that instead of failing obscurely")
    func noRemote() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)

        #expect(throws: GitClientError.noRemote) { try client.push() }
        #expect(throws: GitClientError.noRemote) { try client.fetch() }
    }
}
