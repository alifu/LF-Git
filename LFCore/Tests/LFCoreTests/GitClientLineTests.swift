import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git client: lines, patches, blame, compare, bisect, ignore")
struct GitClientLineTests {
    private static let base = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n"

    /// A file where line 2 and line 4 are changed and one line is added after line 9, in the same hunk.
    private func editedFixture() throws -> (GitFixture, GitClient) {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", Self.base)
        let edited = Self.base
            .replacingOccurrences(of: "line 2\n", with: "line 2 new\n")
            .replacingOccurrences(of: "line 4\n", with: "line 4 new\n")
        fixture.sandbox.write("f.txt", edited)
        return (fixture, GitClient(directory: fixture.directory))
    }

    /// The numbers of diff lines whose text starts with `prefix` (e.g. "+line 2").
    private func diffLines(_ diff: GitDiffFile, starting prefix: String) -> Set<Int> {
        Set((1...diff.lineCount).filter { diff.text(ofLine: $0).hasPrefix(prefix) })
    }

    @Test("only the selected lines of a hunk are staged")
    func stageLines() throws {
        let (fixture, client) = try editedFixture()
        defer { withExtendedLifetime(fixture) {} }
        let diff = try client.diff(of: .workingTree(path: "f.txt", staged: false))
        let hunk = try #require(diff.index.hunks.first)
        // Stage only the change of line 2 (its - and + lines).
        let chosen = diffLines(diff, starting: "-line 2").union(diffLines(diff, starting: "+line 2"))

        try client.applyLines(chosen, in: hunk, of: diff, stage: true)

        let staged = try fixture.git.run(["diff", "--cached", "-U0"]).text
        #expect(staged.contains("+line 2 new"))
        #expect(!staged.contains("line 4"))
        let unstaged = try fixture.git.run(["diff", "-U0"]).text
        #expect(unstaged.contains("+line 4 new"))
        #expect(!unstaged.contains("line 2"))
    }

    @Test("selecting only the added half of a change stages an insertion and keeps the removal unstaged")
    func halfChange() throws {
        let (fixture, client) = try editedFixture()
        defer { withExtendedLifetime(fixture) {} }
        let diff = try client.diff(of: .workingTree(path: "f.txt", staged: false))
        let hunk = try #require(diff.index.hunks.first)

        try client.applyLines(diffLines(diff, starting: "+line 2"), in: hunk, of: diff, stage: true)

        let staged = try fixture.git.run(["show", ":f.txt"]).stdout
        let text = String(decoding: staged, as: UTF8.self)
        #expect(text.contains("line 2\nline 2 new\n"), "the old line stays and the new one is added after it")
    }

    @Test("staged lines can be unstaged one by one")
    func unstageLines() throws {
        let (fixture, client) = try editedFixture()
        defer { withExtendedLifetime(fixture) {} }
        try client.stage(["f.txt"])
        let diff = try client.diff(of: .workingTree(path: "f.txt", staged: true))
        let hunk = try #require(diff.index.hunks.first)
        let chosen = diffLines(diff, starting: "-line 4").union(diffLines(diff, starting: "+line 4"))

        try client.applyLines(chosen, in: hunk, of: diff, stage: false)

        let staged = try fixture.git.run(["diff", "--cached", "-U0"]).text
        #expect(staged.contains("+line 2 new"))
        #expect(!staged.contains("line 4"))
    }

    @Test("selected lines are discarded from the work tree only")
    func discardLines() throws {
        let (fixture, client) = try editedFixture()
        defer { withExtendedLifetime(fixture) {} }
        let diff = try client.diff(of: .workingTree(path: "f.txt", staged: false))
        let hunk = try #require(diff.index.hunks.first)
        let chosen = diffLines(diff, starting: "-line 2").union(diffLines(diff, starting: "+line 2"))

        try client.discardLines(chosen, in: hunk, of: diff)

        let text = fixture.read("f.txt")
        #expect(text.contains("line 2\n"))
        #expect(!text.contains("line 2 new"))
        #expect(text.contains("line 4 new"))
    }

    @Test("a selection without any change line is an error, not an empty patch")
    func emptySelection() throws {
        let (fixture, client) = try editedFixture()
        defer { withExtendedLifetime(fixture) {} }
        let diff = try client.diff(of: .workingTree(path: "f.txt", staged: false))
        let hunk = try #require(diff.index.hunks.first)

        #expect(throws: GitClientError.self) { try client.applyLines([], in: hunk, of: diff, stage: true) }
    }

    @Test("lines of an old commit can be applied to the work tree, forward or backward")
    func patchFromCommit() throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", Self.base, message: "base")
        let changed = Self.base.replacingOccurrences(of: "line 5\n", with: "line 5 new\n")
        try fixture.commit("f.txt", changed, message: "change 5")
        try fixture.commit("g.txt", "other\n", message: "other")
        let client = GitClient(directory: fixture.directory)
        let commit = try #require(try client.log().first { $0.subject == "change 5" })
        let diff = try client.diff(of: .commit(commit, path: "f.txt"))
        let hunk = try #require(diff.index.hunks.first)
        let all = diffLines(diff, starting: "-line 5").union(diffLines(diff, starting: "+line 5"))

        // Backward = revert those lines in the work tree.
        try client.applyCommitLines(all, in: hunk, of: diff, to: .workingTree, reverse: true)
        #expect(fixture.read("f.txt") == Self.base)
        // Forward again.
        try client.applyCommitLines(all, in: hunk, of: diff, to: .workingTree, reverse: false)
        #expect(fixture.read("f.txt") == changed)
    }

    @Test("a commit's lines can be removed from that commit")
    func removeFromCommit() throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", Self.base, message: "base")
        let changed = Self.base
            .replacingOccurrences(of: "line 2\n", with: "line 2 new\n")
            .replacingOccurrences(of: "line 9\n", with: "line 9 new\n")
        try fixture.commit("f.txt", changed, message: "two changes")
        try fixture.commit("g.txt", "other\n", message: "later")
        let client = GitClient(directory: fixture.directory)
        let commit = try #require(try client.log().first { $0.subject == "two changes" })
        let diff = try client.diff(of: .commit(commit, path: "f.txt"))
        let hunk = try #require(diff.index.hunks.first)
        let chosen = diffLines(diff, starting: "-line 9").union(diffLines(diff, starting: "+line 9"))

        try client.removeLines(chosen, in: hunk, of: diff, from: commit)

        #expect(try client.log().map(\.subject) == ["later", "two changes", "base"])
        let rewritten = try #require(try client.log().first { $0.subject == "two changes" })
        let now = try fixture.git.run(["show", "\(rewritten.hash):f.txt"]).text
        #expect(now.contains("line 2 new"))
        #expect(now.contains("line 9\n") || now.hasSuffix("line 10"))
        #expect(!now.contains("line 9 new"))
        #expect(fixture.read("g.txt") == "other\n")
        #expect(try client.operation() == nil)
    }

    // MARK: Blame

    @Test("blame names the commit and author of every line")
    func blame() throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", "a\nb\nc\n", message: "first")
        try fixture.commit("f.txt", "a\nB\nc\n", message: "second")
        let client = GitClient(directory: fixture.directory)

        let lines = try client.blame(path: "f.txt")

        #expect(lines.map(\.content) == ["a", "B", "c"])
        #expect(lines.map(\.number) == [1, 2, 3])
        #expect(lines.map(\.summary) == ["first", "second", "first"])
        #expect(lines[1].author == "Test")
        #expect(lines[0].hash != lines[1].hash)
    }

    @Test("blame at an older revision shows the older authorship")
    func blameRevision() throws {
        let fixture = try GitFixture()
        let first = try fixture.commit("f.txt", "a\nb\n", message: "first")
        try fixture.commit("f.txt", "a\nB\n", message: "second")
        let client = GitClient(directory: fixture.directory)

        let lines = try client.blame(path: "f.txt", revision: first)

        #expect(lines.map(\.summary) == ["first", "first"])
    }

    // MARK: File history and filters

    @Test("the history of one file follows its renames")
    func fileHistory() throws {
        let fixture = try GitFixture()
        try fixture.commit("old.txt", "1\n", message: "create")
        try fixture.commit("other.txt", "x\n", message: "unrelated")
        try fixture.git.run(["mv", "old.txt", "new.txt"])
        try fixture.commitAll("rename")
        try fixture.commit("new.txt", "2\n", message: "edit")
        let client = GitClient(directory: fixture.directory)

        let history = try client.log(filter: GitLogFilter(path: "new.txt", followRenames: true))

        #expect(history.map(\.subject) == ["edit", "rename", "create"])
    }

    @Test("history filters: text, author and merges")
    func filters() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "fix: crash on start")
        try fixture.commit("a.txt", "2\n", message: "feat: new button")
        try fixture.git.run(["-c", "user.name=Someone Else", "commit", "--allow-empty", "-q", "-m", "chore: empty"])
        let client = GitClient(directory: fixture.directory)

        #expect(try client.log(filter: GitLogFilter(message: "crash")).map(\.subject) == ["fix: crash on start"])
        #expect(try client.log(filter: GitLogFilter(author: "Someone")).map(\.subject) == ["chore: empty"])
        #expect(try client.log(filter: GitLogFilter(message: "-x")).isEmpty, "option-like text is searched for, not run")
    }

    // MARK: Compare

    @Test("two revisions are compared: changed files and a file's diff")
    func compare() throws {
        let fixture = try GitFixture()
        let first = try fixture.commit("a.txt", "1\n", message: "one")
        try fixture.commit("b.txt", "new\n", message: "two")
        let last = try fixture.commit("a.txt", "2\n", message: "three")
        let client = GitClient(directory: fixture.directory)

        let files = try client.changedFiles(from: first, to: last)
        #expect(files.map(\.path).sorted() == ["a.txt", "b.txt"])
        let diff = try client.diff(of: .range(from: first, to: last, path: "a.txt"))
        #expect(diff.index.hunks.count == 1)
        #expect(throws: GitClientError.self) { try client.changedFiles(from: "--output=x", to: last) }
    }

    // MARK: Diff options

    @Test("diff options: ignore whitespace and a different context size")
    func diffOptions() throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", Self.base)
        fixture.sandbox.write("f.txt", Self.base.replacingOccurrences(of: "line 5\n", with: "line 5   \n"))
        let client = GitClient(directory: fixture.directory)

        let plain = try client.diff(of: .workingTree(path: "f.txt", staged: false))
        #expect(plain.index.hunks.count == 1)
        let ignoring = try client.diff(of: .workingTree(path: "f.txt", staged: false),
                                       options: DiffOptions(ignoreWhitespace: true))
        #expect(ignoring.index.hunks.isEmpty)

        fixture.sandbox.write("f.txt", Self.base.replacingOccurrences(of: "line 5\n", with: "line 5 x\n"))
        let narrow = try client.diff(of: .workingTree(path: "f.txt", staged: false), options: DiffOptions(contextLines: 0))
        let wide = try client.diff(of: .workingTree(path: "f.txt", staged: false), options: DiffOptions(contextLines: 8))
        #expect(narrow.lineCount < plain.lineCount)
        #expect(wide.lineCount > plain.lineCount)
        #expect(narrow.isStageable)
        #expect(!ignoring.isStageable)
    }

    // MARK: Bisect

    @Test("bisect narrows down the first bad commit")
    func bisect() throws {
        let fixture = try GitFixture()
        var commits: [String] = []
        for n in 1...8 {
            commits.append(try fixture.commit("v.txt", (n >= 6 ? "bad" : "good") + " \(n)\n", message: "c\(n)"))
        }
        let client = GitClient(directory: fixture.directory)
        #expect(try !client.isBisecting())

        var step = try client.bisectStart(bad: commits[7], good: commits[0])
        #expect(try client.isBisecting())
        var guardCounter = 0
        while case .testing = step, guardCounter < 10 {
            guardCounter += 1
            let isBad = fixture.read("v.txt").hasPrefix("bad")
            step = try client.bisectMark(isBad ? .bad : .good)
        }

        guard case .found(let culprit) = step else {
            Issue.record("bisect did not finish: \(step)")
            return
        }
        #expect(culprit == commits[5])
        try client.bisectReset()
        #expect(try !client.isBisecting())
    }

    // MARK: Ignore

    @Test("files are added to .gitignore or the local exclude file, literally")
    func ignore() throws {
        let fixture = try GitFixture()
        try fixture.commit("keep.txt", "1\n")
        fixture.sandbox.write("[ab].txt", "odd\n")
        fixture.sandbox.write("a.txt", "plain\n")
        fixture.sandbox.write("local.txt", "mine\n")
        let client = GitClient(directory: fixture.directory)

        try client.ignore(["[ab].txt"], scope: .gitignore)
        try client.ignore(["local.txt"], scope: .localExclude)

        #expect(fixture.read(".gitignore").contains("/\\[ab\\].txt"))
        let status = try client.status()
        #expect(status.unstaged.filter { $0.kind == .untracked }.map(\.path).sorted() == [".gitignore", "a.txt"])
    }

    @Test("ignoring a tracked file also stops tracking it")
    func ignoreTracked() throws {
        let fixture = try GitFixture()
        try fixture.commit("secret.txt", "s\n")
        let client = GitClient(directory: fixture.directory)

        try client.ignore(["secret.txt"], scope: .gitignore)

        #expect(FileManager.default.fileExists(atPath: fixture.sandbox.path("secret.txt")))
        #expect(try client.status().staged.map(\.path).contains("secret.txt"))
    }
}
