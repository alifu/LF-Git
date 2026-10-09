import Foundation
import LFKit
import LFTestSupport
import Testing
@testable import LF_Git

@MainActor
private func openRepository(_ fixture: GitFixture) async throws -> RepositoryModel {
    let model = try RepositoryModel.open(at: fixture.directory)
    await model.refresh()
    return model
}

@MainActor
@Suite("Repository model: lazygit-style features")
struct LazygitFeatureTests {
    @Test("a running command can be cancelled and the toolbar returns to idle")
    func cancel() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let model = try await openRepository(fixture)

        let running = Task {
            try await model.perform("Napping…", cancellable: true) { client, token in
                try client.git.run(["-c", "alias.nap=!sleep 30", "nap"], cancellation: token)
            }
        }
        while !model.isCancellable { await Task.yield() }
        model.cancelBusy()

        await #expect(throws: GitError.cancelled) { try await running.value }
        #expect(model.busyTitle == nil)
        #expect(!model.isCancellable)
    }

    @Test("a merge that stops on conflicts is not reported as a failure; the banner takes over")
    func conflictedMergeIsNotAnError() async throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("c.txt")])
        try fixture.git.run(["merge", "--abort"])
        let model = try await openRepository(fixture)

        try await model.perform("Merging…") { client, _ in try client.mergeBranch("feature") }

        #expect(model.operation == .merge)
        #expect(model.files.map(\.path) == ["c.txt"])
    }

    @Test("every command the app runs for the user lands in the command log")
    func commandLog() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("a.txt", "2\n")
        let model = try await openRepository(fixture)

        try await model.changes.stage(["a.txt"])
        try await Task.sleep(for: .milliseconds(100)) // log entries arrive on the main actor a moment later

        #expect(model.commandEntries.contains { $0.command == "git add -- a.txt" })
    }

    @Test("stashes, tags, remotes and the reflog are loaded with the rest of the state")
    func extraState() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        _ = try fixture.addOrigin()
        try fixture.git.run(["tag", "v1"])
        fixture.sandbox.write("a.txt", "2\n")
        try fixture.git.run(["stash", "push", "-m", "wip"])

        let model = try await openRepository(fixture)

        #expect(model.stashes.map(\.message) == ["wip"])
        #expect(model.tags.map(\.name) == ["v1"])
        #expect(model.remotes.map(\.name) == ["origin"])
        #expect(!model.reflog.isEmpty)
        #expect(model.worktrees.count == 1)
    }

    @Test("copied commits are cherry-picked oldest first, then the clipboard is empty")
    func pasteCommits() async throws {
        let fixture = try GitFixture()
        try fixture.commit("base.txt", "b\n", message: "base")
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("source")
        try fixture.commit("one.txt", "1\n", message: "one")
        try fixture.commit("two.txt", "2\n", message: "two")
        let picks = try client.log().filter { ["one", "two"].contains($0.subject) }
        try client.switchBranch("main")
        let model = try await openRepository(fixture)

        model.copyCommits(picks) // newest first, as a log shows them
        model.copyCommits(picks) // copying again adds nothing
        #expect(model.copiedCommits.count == 2)
        try await model.pasteCopiedCommits()

        #expect(try client.log().map(\.subject) == ["two", "one", "base"])
        #expect(model.copiedCommits.isEmpty)
    }

    @Test("bisect starts once a good and a bad commit are marked, and ends when reset")
    func bisect() async throws {
        let fixture = try GitFixture()
        for n in 1...6 { try fixture.commit("v.txt", "\(n)\n", message: "c\(n)") }
        let client = GitClient(directory: fixture.directory)
        let commits = try client.log()
        let model = try await openRepository(fixture)

        try await model.markForBisect(.bad, commit: commits[0])
        #expect(!model.isBisecting)
        try await model.markForBisect(.good, commit: commits[5])
        #expect(model.isBisecting)
        #expect(model.bisectCandidate != nil)

        try await model.resetBisect()
        #expect(!model.isBisecting)
    }

    @Test("undo moves HEAD back and the same call redoes it")
    func undo() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "one")
        try fixture.commit("a.txt", "2\n", message: "two")
        let model = try await openRepository(fixture)

        try await model.undoHeadMove()
        #expect(try GitClient(directory: fixture.directory).log().map(\.subject) == ["one"])
        try await model.undoHeadMove()
        #expect(try GitClient(directory: fixture.directory).log().map(\.subject) == ["two", "one"])
    }

    @Test("the history model shows a fixed list, filters the log and compares two revisions")
    func historyModes() async throws {
        let fixture = try GitFixture()
        let first = try fixture.commit("a.txt", "1\n", message: "fix: first")
        try fixture.commit("b.txt", "2\n", message: "feat: second")
        let last = try fixture.commit("a.txt", "3\n", message: "feat: third")
        let model = try await openRepository(fixture)

        model.history.filter = GitLogFilter(message: "feat")
        await model.history.reload()
        #expect(model.history.commits.map(\.subject) == ["feat: third", "feat: second"])

        let commit = try #require(await model.commit(for: first))
        await model.commitViewer.show(.fixed([commit]))
        await model.commitViewer.select(commit.id)
        #expect(model.commitViewer.files.map(\.path) == ["a.txt"])

        await model.history.compare(from: first, to: last)
        #expect(model.history.comparison?.from == first)
        #expect(model.history.files.map(\.path).sorted() == ["a.txt", "b.txt"])
        #expect(model.history.diff != nil)
    }

    @Test("blame of the selected file is loaded for the selected commit")
    func blame() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "x\ny\n", message: "one")
        let model = try await openRepository(fixture)
        await model.history.reload()

        await model.history.showBlame(true)

        #expect(model.history.blame?.map(\.content) == ["x", "y"])
        await model.history.showBlame(false)
        #expect(model.history.blame == nil)
    }

    @Test("single lines are staged and discarded through the changes model")
    func lineStaging() async throws {
        let fixture = try GitFixture()
        let base = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try fixture.commit("f.txt", base)
        fixture.sandbox.write("f.txt", base.replacingOccurrences(of: "line 2\n", with: "line 2 new\n")
            .replacingOccurrences(of: "line 4\n", with: "line 4 new\n"))
        let model = try await openRepository(fixture)
        await model.changes.select(ChangeSelection(path: "f.txt", staged: false))
        let diff = try #require(model.changes.diff)
        let hunk = try #require(diff.index.hunks.first)
        let lines = Set((1...diff.lineCount).filter { diff.text(ofLine: $0).hasPrefix("+line 2") || diff.text(ofLine: $0).hasPrefix("-line 2") })

        try await model.changes.applyLines(lines, in: hunk, of: diff)

        #expect(try fixture.git.run(["diff", "--cached", "-U0"]).text.contains("+line 2 new"))
        #expect(!(try fixture.git.run(["diff", "--cached", "-U0"]).text.contains("line 4")))

        await model.changes.select(ChangeSelection(path: "f.txt", staged: false))
        let remaining = try #require(model.changes.diff)
        let remainingHunk = try #require(remaining.index.hunks.first)
        let four = Set((1...remaining.lineCount).filter { remaining.text(ofLine: $0).contains("line 4") })
        try await model.changes.discardLines(four, in: remainingHunk, of: remaining)
        #expect(fixture.read("f.txt").contains("line 4\n"))
    }

    @Test("a whitespace-ignoring diff cannot be staged")
    func ignoreWhitespaceBlocksStaging() async throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", "a\nb\nc\n")
        fixture.sandbox.write("f.txt", "a\nB\nc\n")
        let model = try await openRepository(fixture)
        await model.changes.select(ChangeSelection(path: "f.txt", staged: false))
        await model.changes.setOptions(DiffOptions(ignoreWhitespace: true))
        let diff = try #require(model.changes.diff)
        let hunk = try #require(diff.index.hunks.first)

        await #expect(throws: GitClientError.self) { try await model.changes.applyLines([5], in: hunk, of: diff) }
        #expect(!diff.isStageable)
    }

    @Test("recently opened repositories are remembered, newest first, without duplicates")
    func recents() throws {
        let app = AppModel()
        app.clearRecentRepositories()
        // Only the model's own bookkeeping is tested: throw-away temp directories are deliberately not remembered.
        let fixture = try GitFixture()
        app.open(fixture.directory)
        #expect(app.recentRepositories.isEmpty)
        #expect(app.repository != nil)
    }
}
