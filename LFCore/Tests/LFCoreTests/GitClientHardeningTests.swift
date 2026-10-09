import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git client hardening")
struct GitClientHardeningTests {
    @Test("a file named like a glob is discarded alone, not together with everything it matches")
    func literalPathspecs() throws {
        let fixture = try GitFixture()
        try fixture.commit("keep.txt", "1\n")
        fixture.sandbox.write("*.log", "the odd one\n")
        fixture.sandbox.write("a.log", "must survive\n")
        fixture.sandbox.write("b.log", "must survive too\n")
        let client = GitClient(directory: fixture.directory)

        try client.discard(try client.status().unstaged.filter { $0.path == "*.log" })

        #expect(!FileManager.default.fileExists(atPath: fixture.sandbox.path("*.log")))
        #expect(FileManager.default.fileExists(atPath: fixture.sandbox.path("a.log")))
        #expect(FileManager.default.fileExists(atPath: fixture.sandbox.path("b.log")))
    }

    @Test("staging a glob-like name stages only that file")
    func literalStage() throws {
        let fixture = try GitFixture()
        try fixture.commit("keep.txt", "1\n")
        fixture.sandbox.write("[ab].txt", "odd\n")
        fixture.sandbox.write("a.txt", "plain\n")
        let client = GitClient(directory: fixture.directory)

        try client.stage(["[ab].txt"])

        #expect(try client.status().staged.map(\.path) == ["[ab].txt"])
    }

    @Test("Git.run passes extra environment variables")
    func environment() throws {
        let fixture = try GitFixture()

        let env = try fixture.git.run(["-c", "alias.showenv=!env", "showenv"], environment: ["LFGIT_PROBE": "yes"]).text

        #expect(env.contains("LFGIT_PROBE=yes"))
        #expect(env.contains("GIT_LITERAL_PATHSPECS=1"))
    }

    @Test("history is listed so that children come before their parents, even with skewed clocks")
    func topologicalOrder() throws {
        let fixture = try GitFixture()
        func commit(_ file: String, _ message: String, date: String) throws -> String {
            fixture.sandbox.write(file, message)
            try fixture.git.run(["add", "-A"])
            try fixture.git.run(["commit", "-q", "-m", message], environment: ["GIT_COMMITTER_DATE": date, "GIT_AUTHOR_DATE": date])
            return try fixture.git.run(["rev-parse", "HEAD"]).text
        }
        let root = try commit("a.txt", "root", date: "2030-01-01T00:00:00")  // newer than its children
        try fixture.git.run(["checkout", "-q", "-b", "side"])
        let side = try commit("b.txt", "side", date: "2025-01-01T00:00:00")
        try fixture.git.run(["checkout", "-q", "main"])
        let tip = try commit("c.txt", "tip", date: "2020-01-01T00:00:00")

        let hashes = try GitClient(directory: fixture.directory).log(allBranches: true).map(\.hash)

        let position = Dictionary(uniqueKeysWithValues: hashes.enumerated().map { ($1, $0) })
        #expect(position[root]! > position[side]!)
        #expect(position[root]! > position[tip]!)
    }

    @Test("control characters in a commit subject do not break parsing or paging")
    func oddSubjects() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "first")
        try fixture.commit("a.txt", "2\n", message: "weird \u{1F} unit \u{1E} record separators")
        try fixture.commit("a.txt", "3\n", message: "last")
        let client = GitClient(directory: fixture.directory)

        let all = try client.log()
        let second = try client.log(maxCount: 1, skip: 1)

        #expect(all.map(\.subject) == ["last", "weird \u{1F} unit \u{1E} record separators", "first"])
        #expect(second.map(\.subject) == ["weird \u{1F} unit \u{1E} record separators"])
    }

    @Test("a file edited after it was added can be unstaged before the first commit")
    func unstageAfterEditInitial() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write("a.txt", "one\n")
        let client = GitClient(directory: fixture.directory)
        try client.stage(["a.txt"])
        fixture.sandbox.write("a.txt", "two\n")

        try client.unstage(["a.txt"])

        #expect(try client.status().staged.isEmpty)
        #expect(fixture.read("a.txt") == "two\n")
    }

    @Test("branch names and start points that look like options are refused")
    func optionLikeNames() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)

        #expect(throws: GitClientError.self) { try client.createBranch("-x") }
        #expect(throws: GitClientError.self) { try client.createBranch("ok", from: "--discard-changes") }
        #expect(throws: GitClientError.self) { try client.deleteBranch("-D") }
        #expect(throws: GitClientError.self) { try client.switchBranch("--force") }
        #expect(try client.branches().map(\.name) == ["main"])
    }

    @Test("diffs ignore textconv filters, so hunks stay applicable")
    func noTextconv() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write(".gitattributes", "*.txt diff=shout\n")
        try fixture.git.run(["config", "diff.shout.textconv", "tr a-z A-Z <"])
        try fixture.commit("f.txt", "one\ntwo\nthree\n")
        fixture.sandbox.write("f.txt", "one\ntwo changed\nthree\n")

        let diff = try GitClient(directory: fixture.directory).diff(of: .workingTree(path: "f.txt", staged: false))

        let lines = (1...diff.lineCount).map { diff.text(ofLine: $0) }
        #expect(lines.contains("+two changed"))
    }

    @Test("old temporary diff files are swept, fresh ones are kept")
    func sweep() throws {
        let directory = FileManager.default.temporaryDirectory
        let old = directory.appendingPathComponent("lfgit-diff-\(UUID().uuidString).diff")
        let fresh = directory.appendingPathComponent("lfgit-diff-\(UUID().uuidString).diff")
        for url in [old, fresh] { FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8)) }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -2 * 86_400)], ofItemAtPath: old.path)
        defer { try? FileManager.default.removeItem(at: fresh) }

        GitDiffFile.sweepStaleTemporaryFiles(olderThan: 86_400)

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }
}
