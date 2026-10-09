import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git client: branch operations")
struct GitClientBranchOpsTests {
    private func subjects(_ client: GitClient) throws -> [String] {
        try client.log().map(\.subject)
    }

    @Test("a branch is renamed")
    func rename() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("old")

        try client.renameBranch("old", to: "new")

        #expect(try client.branches().map(\.name).sorted() == ["main", "new"])
        #expect(throws: GitClientError.self) { try client.renameBranch("new", to: "-x") }
    }

    @Test("merge: default, no-fast-forward, fast-forward-only and squash")
    func merge() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "base")
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("topic")
        try fixture.commit("b.txt", "topic\n", message: "topic work")
        try client.switchBranch("main")

        try client.mergeBranch("topic", mode: .fastForwardOnly)
        #expect(try subjects(client) == ["topic work", "base"])

        try client.reset(to: "HEAD~1", mode: .hard)
        try client.mergeBranch("topic", mode: .noFastForward)
        #expect(try client.log().first?.isMerge == true)

        try client.reset(to: "HEAD~1", mode: .hard)
        try client.mergeBranch("topic", mode: .squash)
        #expect(try client.status().staged.map(\.path) == ["b.txt"])
        #expect(try subjects(client) == ["base"])
    }

    @Test("a merge that conflicts leaves the operation in progress")
    func mergeConflict() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("c.txt")])
        try fixture.git.run(["merge", "--abort"])
        let client = GitClient(directory: fixture.directory)

        #expect(throws: GitError.self) { try client.mergeBranch("feature", mode: .default) }

        #expect(try client.operation() == .merge)
    }

    @Test("rebase onto another branch replays the commits")
    func rebaseOnto() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "base")
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("topic")
        try fixture.commit("b.txt", "topic\n", message: "topic work")
        try client.switchBranch("main")
        try fixture.commit("c.txt", "main\n", message: "main work")
        try client.switchBranch("topic")

        try client.rebase(onto: "main")

        #expect(try subjects(client) == ["topic work", "main work", "base"])
    }

    @Test("reset moves the branch: soft keeps the index, mixed keeps the files, hard drops them")
    func reset() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        try fixture.commit("a.txt", "2\n", message: "two")
        let client = GitClient(directory: fixture.directory)

        try client.reset(to: "HEAD~1", mode: .soft)
        #expect(try client.status().staged.map(\.path) == ["a.txt"])

        try client.reset(to: "HEAD", mode: .mixed)
        #expect(try client.status().unstaged.map(\.path) == ["a.txt"])
        #expect(fixture.read("a.txt") == "2\n")

        try client.reset(to: "HEAD", mode: .hard)
        #expect(fixture.read("a.txt") == "1\n")
        #expect(throws: GitClientError.self) { try client.reset(to: "--hard", mode: .soft) }
    }

    @Test("an upstream is set and unset")
    func upstream() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        _ = try fixture.addOrigin()
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("topic")

        try client.setUpstream(of: "topic", to: "origin/main")
        #expect(try client.branches().first { $0.name == "topic" }?.upstream == "origin/main")

        try client.unsetUpstream(of: "topic")
        #expect(try client.branches().first { $0.name == "topic" }?.upstream == nil)
    }

    @Test("a remote branch is deleted")
    func deleteRemoteBranch() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let bare = try fixture.addOrigin()
        try fixture.git.run(["push", "-q", "origin", "main:extra"])
        let client = GitClient(directory: fixture.directory)

        try client.deleteRemoteBranch("extra", on: "origin")

        #expect(try Git(directory: bare).run(["branch", "--list", "extra"]).text.isEmpty)
    }

    @Test("another branch is fast-forwarded to its upstream without checking it out")
    func fastForward() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        let bare = try fixture.addOrigin()
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("other")
        try client.switchBranch("main")
        let peer = try GitFixture(cloning: bare)
        try peer.commit("b.txt", "2\n", message: "two")
        try peer.git.run(["push", "-q", "origin", "main"])
        try fixture.git.run(["push", "-q", "origin", "main:other"])
        try client.setUpstream(of: "other", to: "origin/other")
        try peer.git.run(["push", "-q", "origin", "main:other"])
        try client.fetch()

        try client.fastForward("other")

        #expect(try fixture.git.run(["log", "-1", "--format=%s", "other"]).text == "two")
        #expect(try fixture.git.run(["branch", "--show-current"]).text == "main")
    }

    @Test("checking out the previous branch, and a forced switch that discards edits")
    func previousAndForce() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("topic")
        try fixture.commit("a.txt", "topic\n")
        try client.switchPrevious()
        #expect(try fixture.git.run(["branch", "--show-current"]).text == "main")

        fixture.sandbox.write("a.txt", "dirty\n")
        #expect(throws: GitError.self) { try client.switchBranch("topic") }
        try client.switchBranch("topic", discardChanges: true)
        #expect(fixture.read("a.txt") == "topic\n")
    }

    @Test("push can force with lease and refuses a stale lease")
    func forcePush() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        try fixture.commit("a.txt", "2\n", message: "two")
        let bare = try fixture.addOrigin()
        let client = GitClient(directory: fixture.directory)
        fixture.sandbox.write("b.txt", "extra\n")
        try client.stage(["b.txt"])
        try client.amendKeepingMessage()
        #expect(throws: GitError.self) { try client.push() }

        try client.push(force: true)

        #expect(try Git(directory: bare).run(["log", "-1", "--format=%s", "main"]).text == "two")
    }
}
