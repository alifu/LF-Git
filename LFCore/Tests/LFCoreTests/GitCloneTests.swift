import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Clone: addresses")
struct RemoteURLTests {
    @Test("accepted addresses", arguments: [
        "https://github.com/alifu/LF-Git.git", "http://gitlab.local/team/app", "ssh://git@host.example:2222/team/app.git",
        "git@github.com:alifu/LF-Git.git", "file:///tmp/some/repo.git",
    ])
    func accepts(_ address: String) throws {
        _ = try RemoteURL.parse(address)
    }

    @Test("rejected addresses", arguments: [
        "", "   ", "-oProxyCommand=evil", "--upload-pack=evil", "ext::sh -c evil", "https://", "ftp://host/repo",
        "/local/path", "https://host/a b", "https://host/a\nb", "git@host", "file://",
    ])
    func rejects(_ address: String) {
        #expect(throws: CloneProblem.self) { try RemoteURL.parse(address) }
    }

    @Test("a login typed into the address is taken out of it")
    func embeddedLogin() throws {
        let url = try RemoteURL.parse("https://me:p%40ss@git.company.com:8443/team/app.git/")

        #expect(url.text == "https://git.company.com:8443/team/app.git")
        #expect(url.embeddedUsername == "me")
        #expect(url.embeddedPassword == "p@ss")
        #expect(url.host == "git.company.com:8443")
        #expect(url.transport == .http)
    }

    @Test("the default folder name is the repository name")
    func repositoryName() throws {
        #expect(try RemoteURL.parse("https://github.com/alifu/LF-Git.git").repositoryName == "LF-Git")
        #expect(try RemoteURL.parse("git@github.com:alifu/tools").repositoryName == "tools")
        #expect(try RemoteURL.parse("ssh://git@host/a/b/").repositoryName == "b")
    }
}

@Suite("Clone: progress and failures")
struct CloneParsingTests {
    @Test("the newest percentage in a chunk of git output wins")
    func progress() {
        let chunk = "Cloning into 'x'...\nremote: Counting objects: 100% (10/10), done.\rReceiving objects:  42% (4/10)\rReceiving objects:  57% (6/10)\r"

        #expect(CloneProgress.latest(in: chunk) == CloneProgress(phase: "Receiving objects", percent: 57))
        #expect(CloneProgress.latest(in: "Cloning into 'x'...\n") == nil)
    }

    @Test("failures are told apart by what git says", arguments: [
        ("fatal: could not read Username for 'https://host': terminal prompts disabled", RemoteFailure.needsLogin),
        ("git@host: Permission denied (publickey).", .needsLogin),
        ("fatal: unable to access 'https://h/': Could not resolve host: h", .unreachable),
        ("fatal: unable to access 'https://h/': Failed to connect to h port 443: Operation timed out", .unreachable),
        ("remote: Repository not found.\nfatal: repository 'https://h/x.git/' not found", .notFound),
        ("fatal: something odd", .other("fatal: something odd")),
    ])
    func classify(stderr: String, expected: RemoteFailure) {
        let error = GitError.failed(arguments: ["ls-remote"], status: 128, stderr: stderr)

        #expect(RemoteFailure.classify(error) == expected)
    }

    @Test("a timeout means the server is unreachable")
    func timeout() {
        #expect(RemoteFailure.classify(.timedOut(seconds: 8)) == .unreachable)
    }
}

@Suite("Clone: from a repository on disk")
struct GitCloneTests {
    /// A remote with `main` and `topic` branches.
    private func remote() throws -> (fixture: GitFixture, url: RemoteURL) {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let origin = try fixture.addOrigin()
        try fixture.git.run(["checkout", "-q", "-b", "topic"])
        try fixture.commit("b.txt", "2\n")
        try fixture.git.run(["push", "-q", "origin", "topic"])
        return (fixture, try RemoteURL.parse("file://\(origin.path)"))
    }

    @Test("the probe lists the branches, default first")
    func probe() throws {
        let (fixture, url) = try remote()
        defer { withExtendedLifetime(fixture) {} }

        let found = try GitClone.probe(url)

        #expect(found.branches == ["main", "topic"])
        #expect(found.defaultBranch == "main")
    }

    @Test("the probe of an empty repository finds no branches")
    func probeEmpty() throws {
        let bare = Sandbox()
        try Git(directory: bare.root).run(["init", "-q", "--bare", "-b", "main"])

        let found = try GitClone.probe(RemoteURL.parse("file://\(bare.root.path)"))

        #expect(found.branches.isEmpty)
        #expect(found.defaultBranch == nil)
    }

    @Test("the probe of a missing repository fails as not found or unreachable-free")
    func probeMissing() throws {
        let url = try RemoteURL.parse("file:///nonexistent/lfgit/repo.git")

        #expect(throws: GitError.self) { try GitClone.probe(url) }
    }

    @Test("a clone checks out the chosen branch")
    func cloneBranch() throws {
        let (fixture, url) = try remote()
        defer { withExtendedLifetime(fixture) {} }
        let parent = Sandbox()

        let destination = try GitClone.clone(CloneRequest(url: url, parent: parent.root, folderName: "copy", branch: "topic"))

        #expect(try Git(directory: destination).run(["rev-parse", "--abbrev-ref", "HEAD"]).text == "topic")
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("b.txt").path))
    }

    @Test("a clone of one branch leaves the others on the server")
    func singleBranch() throws {
        let (fixture, url) = try remote()
        defer { withExtendedLifetime(fixture) {} }
        let parent = Sandbox()

        let destination = try GitClone.clone(CloneRequest(url: url, parent: parent.root, folderName: "copy", branch: "main"))

        let remotes = try Git(directory: destination).run(["branch", "-r"]).text
        #expect(remotes.contains("origin/main"))
        #expect(!remotes.contains("origin/topic"))
    }

    @Test("a folder that holds something is refused and left alone")
    func occupiedDestination() throws {
        let (fixture, url) = try remote()
        defer { withExtendedLifetime(fixture) {} }
        let parent = Sandbox()
        let target = parent.root.appendingPathComponent("copy")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: target.appendingPathComponent("mine.txt"))

        #expect(throws: CloneProblem.destinationNotEmpty(target.path)) {
            try GitClone.clone(CloneRequest(url: url, parent: parent.root, folderName: "copy"))
        }
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("mine.txt").path))
    }

    @Test("a failed clone removes the folder it made but keeps one that was there")
    func failureCleanup() throws {
        let parent = Sandbox()
        let missing = try RemoteURL.parse("file:///nonexistent/lfgit/repo.git")
        let existing = parent.root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        #expect(throws: GitError.self) { try GitClone.clone(CloneRequest(url: missing, parent: parent.root, folderName: "made")) }
        #expect(throws: GitError.self) { try GitClone.clone(CloneRequest(url: missing, parent: parent.root, folderName: "empty")) }

        #expect(!FileManager.default.fileExists(atPath: parent.root.appendingPathComponent("made").path))
        #expect(FileManager.default.fileExists(atPath: existing.path))
    }

    @Test("a cancelled clone stops and leaves nothing behind")
    func cancelled() throws {
        let (fixture, url) = try remote()
        defer { withExtendedLifetime(fixture) {} }
        let parent = Sandbox()
        let cancellation = GitCancellation()
        cancellation.cancel()

        #expect(throws: GitError.cancelled) {
            try GitClone.clone(CloneRequest(url: url, parent: parent.root, folderName: "copy"), cancellation: cancellation)
        }
        #expect(!FileManager.default.fileExists(atPath: parent.root.appendingPathComponent("copy").path))
    }

    @Test("folder names that could escape the parent are refused", arguments: ["", "..", ".", "a/b", "-x"])
    func badFolderName(_ name: String) throws {
        let (fixture, url) = try remote()
        defer { withExtendedLifetime(fixture) {} }

        #expect(throws: CloneProblem.invalidFolderName) {
            try GitClone.clone(CloneRequest(url: url, parent: Sandbox().root, folderName: name))
        }
    }

    @Test("a login typed in the address reaches git without being logged")
    func passwordStaysOutOfTheLog() throws {
        let (fixture, url) = try remote()
        defer { withExtendedLifetime(fixture) {} }
        let log = GitCommandLog()
        let withLogin = try RemoteURL.parse("https://me:s3cret@example.invalid/x.git")

        _ = try? GitClone.probe(withLogin, timeout: 3, log: log)
        _ = try? GitClone.probe(url, log: log)

        #expect(!log.entries.contains { $0.command.contains("s3cret") })
    }
}
