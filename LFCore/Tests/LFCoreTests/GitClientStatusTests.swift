import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git status")
struct GitStatusTests {
    @Test("a clean repository has a branch, no changes and no upstream")
    func clean() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "one\n")

        let status = try GitClient(directory: fixture.directory).status()

        #expect(status.branch == "main")
        #expect(!status.isDetached)
        #expect(status.upstream == nil)
        #expect(status.entries.isEmpty)
        #expect(status.isClean)
    }

    @Test("a repository without commits reports its branch and staged files")
    func unborn() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write("a.txt", "one\n")
        try fixture.git.run(["add", "a.txt"])

        let status = try GitClient(directory: fixture.directory).status()

        #expect(status.branch == "main")
        #expect(status.commitHash == nil)
        #expect(status.staged.map(\.path) == ["a.txt"])
        #expect(status.staged.first?.index == .added)
    }

    @Test("staged, unstaged, both, deleted, renamed and untracked files are told apart")
    func entries() throws {
        let fixture = try GitFixture()
        try fixture.commit("modified.txt", "1\n")
        try fixture.commit("both.txt", "1\n")
        try fixture.commit("deleted.txt", "1\n")
        try fixture.commit("old name.txt", "same content\nsecond line\nthird line\n")
        fixture.sandbox.write("modified.txt", "2\n")
        fixture.sandbox.write("both.txt", "2\n")
        try fixture.git.run(["add", "both.txt"])
        fixture.sandbox.write("both.txt", "3\n")
        try FileManager.default.removeItem(atPath: fixture.sandbox.path("deleted.txt"))
        try fixture.git.run(["mv", "old name.txt", "néw name.txt"])
        fixture.sandbox.write("untracked file.txt", "new\n")

        let status = try GitClient(directory: fixture.directory).status()

        func change(_ path: String) -> GitChange? { status.entries.first { $0.path == path } }
        #expect(change("modified.txt")?.index == .unmodified)
        #expect(change("modified.txt")?.worktree == .modified)
        #expect(change("both.txt")?.index == .modified)
        #expect(change("both.txt")?.worktree == .modified)
        #expect(change("deleted.txt")?.worktree == .deleted)
        #expect(change("néw name.txt")?.index == .renamed)
        #expect(change("néw name.txt")?.originalPath == "old name.txt")
        #expect(change("untracked file.txt")?.kind == .untracked)
        #expect(Set(status.staged.map(\.path)) == ["both.txt", "néw name.txt"])
        #expect(Set(status.unstaged.map(\.path)) == ["modified.txt", "both.txt", "deleted.txt", "untracked file.txt"])
        #expect(status.conflicted.isEmpty)
    }

    @Test("merge conflicts are listed as unmerged")
    func conflicts() throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])

        let status = try GitClient(directory: fixture.directory).status()

        #expect(status.conflicted.map(\.path) == ["a.txt"])
        #expect(status.staged.isEmpty)
        #expect(!status.isClean)
    }

    @Test("a detached HEAD has no branch name")
    func detached() throws {
        let fixture = try GitFixture()
        let first = try fixture.commit("a.txt", "1\n")
        try fixture.commit("a.txt", "2\n")
        try fixture.git.run(["checkout", "-q", "--detach", first])

        let status = try GitClient(directory: fixture.directory).status()

        #expect(status.isDetached)
        #expect(status.branch == nil)
        #expect(status.commitHash == first)
    }

    @Test("ahead and behind counts follow the upstream")
    func aheadBehind() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let origin = try fixture.addOrigin()
        let other = try GitFixture(cloning: origin)
        try other.commit("b.txt", "from other\n")
        try other.git.run(["push", "-q"])
        try fixture.commit("c.txt", "local 1\n")
        try fixture.commit("c.txt", "local 2\n")
        try fixture.git.run(["fetch", "-q"])

        let status = try GitClient(directory: fixture.directory).status()

        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 2)
        #expect(status.behind == 1)
    }
}

@Suite("Git staging and commit")
struct GitStagingTests {
    @Test("stage and unstage a modified file")
    func stageUnstage() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("a.txt", "2\n")
        let client = GitClient(directory: fixture.directory)

        try client.stage(["a.txt"])
        #expect(try client.status().staged.map(\.path) == ["a.txt"])
        try client.unstage(["a.txt"])

        let status = try client.status()
        #expect(status.staged.isEmpty)
        #expect(status.unstaged.map(\.path) == ["a.txt"])
    }

    @Test("unstaging works before the first commit")
    func unstageInitial() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)
        try client.stage(["a.txt"])

        try client.unstage(["a.txt"])

        #expect(try client.status().staged.isEmpty)
        #expect(try client.status().entries.first?.kind == .untracked)
    }

    @Test("staging a deletion and unstaging a rename restore the right state")
    func deletionAndRename() throws {
        let fixture = try GitFixture()
        try fixture.commit("gone.txt", "1\n")
        try fixture.commit("old.txt", "a\nb\nc\nd\n")
        let client = GitClient(directory: fixture.directory)
        try FileManager.default.removeItem(atPath: fixture.sandbox.path("gone.txt"))
        try client.stage(["gone.txt"])
        #expect(try client.status().staged.first { $0.path == "gone.txt" }?.index == .deleted)

        try fixture.git.run(["mv", "old.txt", "new.txt"])
        try client.unstage(["new.txt", "old.txt"])

        let status = try client.status()
        #expect(status.staged.map(\.path) == ["gone.txt"])
        #expect(FileManager.default.fileExists(atPath: fixture.sandbox.path("new.txt")))
    }

    @Test("discarding restores a tracked file and removes an untracked one")
    func discard() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "original\n")
        fixture.sandbox.write("a.txt", "edited\n")
        fixture.sandbox.write("new.txt", "untracked\n")
        let client = GitClient(directory: fixture.directory)

        try client.discard(try client.status().unstaged)

        #expect(fixture.read("a.txt") == "original\n")
        #expect(!FileManager.default.fileExists(atPath: fixture.sandbox.path("new.txt")))
        #expect(try client.status().isClean)
    }

    @Test("batches split paths so no command line exceeds the byte budget")
    func pathBatches() {
        let paths = (0..<1000).map { "dir/file-\($0).txt" }

        let batches = Git.batches(of: paths, maxBytes: 1000)

        #expect(batches.count > 1)
        #expect(batches.flatMap { $0 } == paths)
        let sizes: [Int] = batches.map { batch in batch.map { $0.utf8.count + 1 }.reduce(0, +) }
        #expect(sizes.allSatisfy { $0 <= 1000 })
        #expect(Git.batches(of: [], maxBytes: 1000).isEmpty)
    }

    @Test("staging and discarding a folder of 20000 untracked files does not overflow the command line")
    func hugeFolder() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "one\n")
        let names = (0..<20_000).map { "big/\(String(repeating: "n", count: 40))-\($0).txt" }
        try FileManager.default.createDirectory(atPath: fixture.sandbox.path("big"), withIntermediateDirectories: true)
        for name in names { fixture.sandbox.write(name, "x\n") }
        let client = GitClient(directory: fixture.directory)

        try client.stage(names)
        #expect(try client.status().staged.count == names.count)
        try client.unstage(names)
        #expect(try client.status().staged.isEmpty)
        try client.discard(try client.status().unstaged)

        #expect(try client.status().isClean)
    }

    @Test("commit records the staged changes and returns the short hash")
    func commit() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("a.txt", "2\n")
        let client = GitClient(directory: fixture.directory)
        try client.stage(["a.txt"])

        let hash = try client.commit(message: "second\n\nbody text")

        #expect(try fixture.git.run(["log", "-1", "--format=%B"]).text == "second\n\nbody text")
        #expect(try fixture.git.run(["rev-parse", "--short", "HEAD"]).text == hash)
        #expect(try client.status().isClean)
    }

    @Test("an empty message or nothing staged is refused with a clear error")
    func refusals() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)

        #expect(throws: GitClientError.emptyMessage) { try client.commit(message: "  \n ") }
        #expect(throws: GitClientError.nothingToCommit) { try client.commit(message: "x") }
    }

    @Test("amend rewrites the last commit with a new message and newly staged changes")
    func amend() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "first")
        try fixture.commit("b.txt", "1\n", message: "typo mesage")
        fixture.sandbox.write("b.txt", "2\n")
        let client = GitClient(directory: fixture.directory)
        try client.stage(["b.txt"])
        #expect(try client.lastCommitMessage() == "typo mesage")

        try client.commit(message: "fixed message", amend: true)

        #expect(try fixture.git.run(["rev-list", "--count", "HEAD"]).text == "2")
        #expect(try fixture.git.run(["log", "-1", "--format=%s"]).text == "fixed message")
        #expect(try fixture.git.run(["show", "HEAD:b.txt"]).text == "2")
    }

    @Test("the last commit message of an empty repository is nil")
    func noLastMessage() throws {
        let fixture = try GitFixture()

        #expect(try GitClient(directory: fixture.directory).lastCommitMessage() == nil)
    }
}

@Suite("Git diff and hunks")
struct GitDiffTests {
    private static let original = (1...40).map { "line \($0)" }.joined(separator: "\n") + "\n"
    /// Changes line 3 and line 38, far enough apart to form two hunks.
    private static let edited = original
        .replacingOccurrences(of: "line 3\n", with: "line 3 changed\n")
        .replacingOccurrences(of: "line 38\n", with: "line 38 changed\n")

    @Test("the parser splits a diff into a file header and hunks with their counts")
    func parser() {
        let text = """
        diff --git a/f.txt b/f.txt
        index 1111111..2222222 100644
        --- a/f.txt
        +++ b/f.txt
        @@ -1,3 +1,4 @@ func title
         a
        +b
         c
         d
        @@ -10 +11 @@
        -x
        +y
        \\ No newline at end of file

        """
        let index = Array(text.utf8).withUnsafeBytes { DiffParser.parse($0) }

        #expect(index.fileHeaderLineCount == 4)
        #expect(index.lineCount == 13)
        #expect(!index.isBinary)
        #expect(index.hunks.count == 2)
        #expect(index.hunks[0].headerLine == 5)
        #expect(index.hunks[0].lineCount == 5)
        #expect(index.hunks[0].oldStart == 1 && index.hunks[0].oldCount == 3)
        #expect(index.hunks[0].newStart == 1 && index.hunks[0].newCount == 4)
        #expect(index.hunks[0].title == "@@ -1,3 +1,4 @@ func title")
        #expect(index.hunks[1].headerLine == 10)
        #expect(index.hunks[1].oldCount == 1 && index.hunks[1].newCount == 1) // omitted counts mean 1
        #expect(index.hunks[1].lineCount == 4)
    }

    @Test("old and new line numbers are tracked for every line of a hunk")
    func lineNumbers() {
        let text = "diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n@@ -1,3 +1,4 @@\n a\n+b\n c\n d\n@@ -10 +11 @@\n-x\n+y\n"
        let index = Array(text.utf8).withUnsafeBytes { DiffParser.parse($0) }

        #expect(index.numbers(ofLine: 1) == (old: 0, new: 0)) // file header
        #expect(index.numbers(ofLine: 4) == (old: 0, new: 0)) // hunk header
        #expect(index.numbers(ofLine: 5) == (old: 1, new: 1)) // " a"
        #expect(index.numbers(ofLine: 6) == (old: 0, new: 2)) // "+b"
        #expect(index.numbers(ofLine: 7) == (old: 2, new: 3)) // " c"
        #expect(index.numbers(ofLine: 8) == (old: 3, new: 4)) // " d"
        #expect(index.numbers(ofLine: 10) == (old: 10, new: 0)) // "-x"
        #expect(index.numbers(ofLine: 11) == (old: 0, new: 11)) // "+y"
        #expect(index.numbers(ofLine: 99) == (old: 0, new: 0)) // outside the diff
    }

    @Test("binary diffs are flagged and have no hunks")
    func binary() {
        let text = "diff --git a/x b/x\nindex 1..2 100644\nBinary files a/x and b/x differ\n"

        let index = Array(text.utf8).withUnsafeBytes { DiffParser.parse($0) }

        #expect(index.isBinary)
        #expect(index.hunks.isEmpty)
    }

    @Test("an unstaged diff lists both hunks and shows their lines")
    func unstagedDiff() throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", Self.original)
        fixture.sandbox.write("f.txt", Self.edited)

        let diff = try GitClient(directory: fixture.directory).diff(of: .workingTree(path: "f.txt", staged: false))

        #expect(diff.index.hunks.count == 2)
        #expect(diff.isDisplayable)
        let added = (1...diff.lineCount).map { diff.text(ofLine: $0) }.filter { $0.hasPrefix("+line") }
        #expect(added == ["+line 3 changed", "+line 38 changed"])
    }

    @Test("staging one hunk leaves the other unstaged, and unstaging reverses it")
    func hunkStaging() throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", Self.original)
        fixture.sandbox.write("f.txt", Self.edited)
        let client = GitClient(directory: fixture.directory)
        let diff = try client.diff(of: .workingTree(path: "f.txt", staged: false))

        try client.applyHunk(diff.index.hunks[0], of: diff, stage: true)

        let staged = try fixture.git.run(["diff", "--cached", "-U0"]).text
        #expect(staged.contains("+line 3 changed"))
        #expect(!staged.contains("line 38 changed"))
        let remaining = try client.diff(of: .workingTree(path: "f.txt", staged: false))
        #expect(remaining.index.hunks.count == 1)
        let stagedDiff = try client.diff(of: .workingTree(path: "f.txt", staged: true))
        try client.applyHunk(stagedDiff.index.hunks[0], of: stagedDiff, stage: false)
        #expect(try client.diff(of: .workingTree(path: "f.txt", staged: true)).index.hunks.isEmpty)
        #expect(try client.diff(of: .workingTree(path: "f.txt", staged: false)).index.hunks.count == 2)
    }

    @Test("a hunk at a file without a final newline can be staged")
    func noNewlineAtEnd() throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", "a\nb\nc")
        fixture.sandbox.write("f.txt", "a\nb\nc changed")
        let client = GitClient(directory: fixture.directory)
        let diff = try client.diff(of: .workingTree(path: "f.txt", staged: false))

        try client.applyHunk(diff.index.hunks[0], of: diff, stage: true)

        #expect(try fixture.git.run(["show", ":f.txt"]).stdout == Data("a\nb\nc changed".utf8))
    }

    @Test("an untracked file shows as all additions")
    func untracked() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("new.txt", "x\ny\n")

        let diff = try GitClient(directory: fixture.directory).diff(of: .untracked(path: "new.txt"))

        #expect(diff.index.hunks.count == 1)
        #expect((1...diff.lineCount).map { diff.text(ofLine: $0) }.contains("+y"))
    }

    @Test("binary files are reported as binary")
    func binaryFile() throws {
        let fixture = try GitFixture()
        fixture.sandbox.write("b.bin", bytes: [0, 1, 2, 3])
        try fixture.commitAll("bin")
        fixture.sandbox.write("b.bin", bytes: [0, 1, 2, 4])

        let diff = try GitClient(directory: fixture.directory).diff(of: .workingTree(path: "b.bin", staged: false))

        #expect(diff.index.isBinary)
    }

    @Test("the temporary diff file is removed when the diff goes away")
    func cleanup() throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", Self.original)
        fixture.sandbox.write("f.txt", Self.edited)
        var url: URL?

        do {
            let diff = try GitClient(directory: fixture.directory).diff(of: .workingTree(path: "f.txt", staged: false))
            url = diff.fileURL
            #expect(FileManager.default.fileExists(atPath: try #require(url).path))
        }

        #expect(!FileManager.default.fileExists(atPath: try #require(url).path))
    }

    @Test("git never takes optional locks, so a background status cannot make a stage fail")
    func noOptionalLocks() throws {
        let fixture = try GitFixture()

        let environment = try fixture.git.run(["-c", "alias.showenv=!env", "showenv"]).text

        #expect(environment.contains("GIT_OPTIONAL_LOCKS=0"))
        #expect(environment.contains("GIT_TERMINAL_PROMPT=0"))
    }

    @Test("Git.run can feed stdin and write stdout to a file")
    func stdinAndFile() throws {
        let fixture = try GitFixture()
        let output = fixture.sandbox.root.appendingPathComponent("out.txt")

        let status = try fixture.git.run(["hash-object", "--stdin"], stdin: Data("hello\n".utf8)).text
        try fixture.git.run(["hash-object", "--stdin"], stdin: Data("hello\n".utf8), outputFile: output)

        #expect(status == "ce013625030ba8dba906f756967f9e9ca394464a")
        #expect(try String(contentsOf: output, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == status)
    }
}
