import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git client: tags, reflog, remotes, worktrees, submodules")
struct GitClientRefsTests {
    // MARK: Tags

    @Test("lightweight and annotated tags are created, listed and deleted")
    func tags() throws {
        let fixture = try GitFixture()
        let first = try fixture.commit("a.txt", "1\n")
        try fixture.commit("a.txt", "2\n")
        let client = GitClient(directory: fixture.directory)

        try client.createTag("v1", at: first)
        try client.createTag("v2", message: "second release")

        let tags = try client.tags()
        #expect(tags.map(\.name).sorted() == ["v1", "v2"])
        let v1 = try #require(tags.first { $0.name == "v1" })
        #expect(v1.commit == first)
        #expect(!v1.isAnnotated)
        let v2 = try #require(tags.first { $0.name == "v2" })
        #expect(v2.isAnnotated)
        #expect(v2.message == "second release")

        try client.deleteTag("v1")
        #expect(try client.tags().map(\.name) == ["v2"])
    }

    @Test("tags are pushed to and deleted from a remote")
    func remoteTags() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let bare = try fixture.addOrigin()
        let client = GitClient(directory: fixture.directory)
        try client.createTag("v1")

        try client.pushTag("v1", to: "origin")
        #expect(try Git(directory: bare).run(["tag"]).text == "v1")

        try client.deleteRemoteTag("v1", on: "origin")
        #expect(try Git(directory: bare).run(["tag"]).text.isEmpty)
    }

    @Test("bad tag names are refused before git sees them")
    func tagNames() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)

        #expect(throws: GitClientError.self) { try client.createTag("-d") }
        #expect(throws: GitClientError.self) { try client.createTag("") }
    }

    // MARK: Reflog

    @Test("the reflog lists HEAD movements, newest first")
    func reflog() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        try fixture.commit("a.txt", "2\n", message: "two")
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("topic")

        let entries = try client.reflog()

        #expect(entries.first?.selector == "HEAD@{0}")
        #expect(entries.first?.message.hasPrefix("checkout: moving from main to topic") == true)
        #expect(entries.contains { $0.message.contains("commit: two") })
        #expect(try client.reflog(maxCount: 1).count == 1)
    }

    // MARK: Remotes

    @Test("remotes are added, renamed, re-pointed and removed")
    func remotes() throws {
        let fixture = try GitFixture()
        let client = GitClient(directory: fixture.directory)

        try client.addRemote("origin", url: "https://example.com/a.git")
        try client.addRemote("backup", url: "https://example.com/b.git")
        #expect(try client.remotes().map(\.name) == ["backup", "origin"])

        try client.renameRemote("backup", to: "mirror")
        try client.setRemoteURL("mirror", url: "https://example.com/c.git")
        let mirror = try #require(try client.remotes().first { $0.name == "mirror" })
        #expect(mirror.fetchURL == "https://example.com/c.git")

        try client.removeRemote("origin")
        #expect(try client.remotes().map(\.name) == ["mirror"])
    }

    @Test("a remote URL or name that looks like an option is refused")
    func remoteInjection() throws {
        let fixture = try GitFixture()
        let client = GitClient(directory: fixture.directory)

        #expect(throws: GitClientError.self) { try client.addRemote("origin", url: "--upload-pack=touch /tmp/x") }
        #expect(throws: GitClientError.self) { try client.addRemote("-x", url: "https://example.com/a.git") }
    }

    @Test("pruning drops remote-tracking branches deleted on the remote")
    func prune() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let bare = try fixture.addOrigin()
        let client = GitClient(directory: fixture.directory)
        try fixture.git.run(["push", "-q", "origin", "main:gone"])
        try client.fetch()
        #expect(try client.branches().contains { $0.name == "origin/gone" })
        try Git(directory: bare).run(["branch", "-D", "gone"])

        try client.pruneRemote("origin")

        #expect(try !client.branches().contains { $0.name == "origin/gone" })
    }

    // MARK: Worktrees

    @Test("a worktree is added on a new branch, listed and removed")
    func worktrees() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)
        let target = Sandbox()
        let path = target.path("wt")

        try client.addWorktree(at: path, branch: "side", createBranch: true)

        let list = try client.worktrees()
        #expect(list.count == 2)
        #expect(list[0].isMain)
        let added = try #require(list.first { !$0.isMain })
        #expect(URL(fileURLWithPath: added.path).resolvingSymlinksInPath().path == URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        #expect(added.branch == "side")

        try client.removeWorktree(at: added.path)
        #expect(try client.worktrees().count == 1)
    }

    // MARK: Submodules

    @Test("a submodule is added, listed, and updated")
    func submodules() throws {
        let library = try GitFixture()
        try library.commit("lib.txt", "lib 1\n")
        let fixture = try GitFixture()
        try fixture.git.run(["config", "protocol.file.allow", "always"])
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)

        try client.addSubmodule(url: library.path, path: "vendor/lib")

        let modules = try client.submodules()
        #expect(modules.count == 1)
        #expect(modules[0].path == "vendor/lib")
        #expect(modules[0].url == library.path)
        #expect(modules[0].state == .upToDate)
        #expect(fixture.read("vendor/lib/lib.txt") == "lib 1\n")

        try library.commit("lib.txt", "lib 2\n")
        try fixture.git.run(["-C", "vendor/lib", "fetch", "-q"])
        try fixture.git.run(["-C", "vendor/lib", "checkout", "-q", "origin/main"])
        #expect(try client.submodules()[0].state == .modified)

        try client.updateSubmodules()
        #expect(try client.submodules()[0].state == .upToDate)
    }

    @Test("a submodule can be removed completely")
    func removeSubmodule() throws {
        let library = try GitFixture()
        try library.commit("lib.txt", "lib 1\n")
        let fixture = try GitFixture()
        try fixture.git.run(["config", "protocol.file.allow", "always"])
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)
        try client.addSubmodule(url: library.path, path: "lib")

        try client.removeSubmodule(path: "lib")

        #expect(try client.submodules().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.sandbox.path("lib")))
    }
}
