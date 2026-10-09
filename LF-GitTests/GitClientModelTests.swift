import Foundation
import LFKit
import LFTestSupport
import Testing
@testable import LF_Git

private let original = (1...40).map { "line \($0)" }.joined(separator: "\n") + "\n"
private let edited = original
    .replacingOccurrences(of: "line 3\n", with: "line 3 changed\n")
    .replacingOccurrences(of: "line 38\n", with: "line 38 changed\n")

@MainActor
private func openRepository(_ fixture: GitFixture) async throws -> RepositoryModel {
    let model = try RepositoryModel.open(at: fixture.directory)
    await model.refresh()
    return model
}

@MainActor
@Suite("Repository git state")
struct RepositoryGitStateTests {
    @Test("refresh reads the status, the branches and any operation in progress")
    func refresh() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        try fixture.git.run(["branch", "other"])
        fixture.sandbox.write("a.txt", "2\n")

        let model = try await openRepository(fixture)

        #expect(model.status.branch == "main")
        #expect(model.status.unstaged.map(\.path) == ["a.txt"])
        #expect(model.branches.map(\.name).sorted() == ["main", "other"])
        #expect(model.operation == nil)
    }

    @Test("the conflicts section is chosen first when there are conflicts, otherwise changes")
    func initialSection() async throws {
        let clean = try GitFixture()
        try clean.commit("a.txt", "1\n")
        let conflicted = try GitFixture()
        try conflicted.makeConflicts([.text("a.txt")])

        #expect(try await openRepository(clean).section == .changes)
        let model = try await openRepository(conflicted)
        #expect(model.section == .conflicts)
        #expect(model.operation == .merge)
    }

    @Test("switching, creating and deleting branches")
    func branches() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let model = try await openRepository(fixture)

        try await model.createBranch("topic")
        #expect(model.status.branch == "topic")
        try await model.switchBranch("main")
        #expect(model.status.branch == "main")
        try await model.deleteBranch("topic")

        #expect(model.branches.map(\.name) == ["main"])
    }

    @Test("a failing switch is reported and the state stays consistent")
    func failingSwitch() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let model = try await openRepository(fixture)

        await #expect(throws: (any Error).self) { try await model.switchBranch("does-not-exist") }
        #expect(model.status.branch == "main")
        #expect(!model.isBusy)
    }

    @Test("aborting a merge returns to a clean state")
    func abort() async throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        let model = try await openRepository(fixture)

        try await model.abortOperation()

        #expect(model.operation == nil)
        #expect(model.files.isEmpty)
    }

    @Test("continuing a merge commits it once the conflicts are resolved")
    func continueMerge() async throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        fixture.sandbox.write("a.txt", "a\nresolved\nc\n")
        let model = try await openRepository(fixture)
        try await model.markResolved("a.txt")

        try await model.continueOperation()

        #expect(model.operation == nil)
        #expect(try fixture.git.run(["rev-list", "--count", "--merges", "HEAD"]).text == "1")
    }

    @Test("fetch, pull and push run against the remote and refresh ahead/behind")
    func remotes() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let origin = try fixture.addOrigin()
        let other = try GitFixture(cloning: origin)
        try other.commit("b.txt", "other\n")
        try GitClient(directory: other.directory).push()
        let model = try await openRepository(fixture)

        try await model.fetch()
        #expect(model.status.behind == 1)
        try await model.pull()
        #expect(model.status.behind == 0)
        try fixture.commit("c.txt", "mine\n")
        await model.refresh()
        #expect(model.status.ahead == 1)
        try await model.push()

        #expect(model.status.ahead == 0)
    }
}

@MainActor
@Suite("Changes model")
struct ChangesModelTests {
    @Test("staging and unstaging a file moves it between the lists and follows the selection")
    func stageUnstage() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("a.txt", "2\n")
        let model = try await openRepository(fixture)
        let changes = model.changes
        changes.selection = ChangeSelection(path: "a.txt", staged: false)

        try await changes.stage(["a.txt"])
        #expect(model.status.staged.map(\.path) == ["a.txt"])
        #expect(changes.selection == ChangeSelection(path: "a.txt", staged: true))

        try await changes.unstage(["a.txt"])
        #expect(model.status.staged.isEmpty)
        #expect(changes.selection == ChangeSelection(path: "a.txt", staged: false))
    }

    @Test("selecting a change loads its diff")
    func diffLoads() async throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", original)
        fixture.sandbox.write("f.txt", edited)
        let model = try await openRepository(fixture)

        await model.changes.select(ChangeSelection(path: "f.txt", staged: false))

        #expect(model.changes.diff?.index.hunks.count == 2)
    }

    @Test("staging one hunk keeps the other unstaged and reloads the diff")
    func hunk() async throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", original)
        fixture.sandbox.write("f.txt", edited)
        let model = try await openRepository(fixture)
        let changes = model.changes
        await changes.select(ChangeSelection(path: "f.txt", staged: false))
        let first = try #require(changes.diff?.index.hunks.first)

        try await changes.applyHunk(first, of: try #require(changes.diff))

        #expect(changes.diff?.index.hunks.count == 1)
        #expect(model.status.staged.map(\.path) == ["f.txt"])
        #expect(model.status.unstaged.map(\.path) == ["f.txt"])
        #expect(changes.selection == ChangeSelection(path: "f.txt", staged: false))
    }

    @Test("stage all and unstage all")
    func all() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("a.txt", "2\n")
        fixture.sandbox.write("new.txt", "n\n")
        let model = try await openRepository(fixture)

        try await model.changes.stageAll()
        #expect(model.status.unstaged.isEmpty)
        #expect(model.status.staged.count == 2)
        try await model.changes.unstageAll()

        #expect(model.status.staged.isEmpty)
    }

    @Test("commit records the staged files, clears the message and refreshes")
    func commit() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("a.txt", "2\n")
        let model = try await openRepository(fixture)
        let changes = model.changes
        try await changes.stage(["a.txt"])
        changes.commitMessage = "second"

        let hash = try await changes.commit()

        #expect(!hash.isEmpty)
        #expect(changes.commitMessage.isEmpty)
        #expect(model.status.isClean)
        #expect(try fixture.git.run(["log", "-1", "--format=%s"]).text == "second")
    }

    @Test("committing is only possible with a message and staged changes")
    func canCommit() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("a.txt", "2\n")
        let model = try await openRepository(fixture)
        let changes = model.changes

        #expect(!changes.canCommit)
        try await changes.stage(["a.txt"])
        #expect(!changes.canCommit) // no message yet
        changes.commitMessage = "x"
        #expect(changes.canCommit)
        await #expect(throws: GitClientError.emptyMessage) {
            changes.commitMessage = " "
            _ = try await changes.commit()
        }
    }

    @Test("turning on amend fills in the last commit message once")
    func amend() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "the last message")
        let model = try await openRepository(fixture)
        let changes = model.changes

        await changes.setAmend(true)
        #expect(changes.commitMessage == "the last message")
        changes.commitMessage = "my own edit"
        await changes.setAmend(false)
        await changes.setAmend(true)

        #expect(changes.commitMessage == "my own edit") // an existing message is never overwritten
        #expect(changes.canCommit) // amend needs no staged changes
    }

    @Test("discarding removes the edit and an untracked file")
    func discard() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("a.txt", "2\n")
        fixture.sandbox.write("new.txt", "n\n")
        let model = try await openRepository(fixture)

        try await model.changes.discard(model.status.unstaged)

        #expect(model.status.isClean)
        #expect(fixture.read("a.txt") == "1\n")
    }

    @Test("a selection that no longer exists is dropped")
    func selectionDropped() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        fixture.sandbox.write("a.txt", "2\n")
        let model = try await openRepository(fixture)
        await model.changes.select(ChangeSelection(path: "a.txt", staged: false))
        try fixture.git.run(["checkout", "--", "a.txt"])

        await model.refresh()

        #expect(model.changes.selection == nil)
        #expect(model.changes.diff == nil)
    }
}

@MainActor
@Suite("Changes model: races and hardening")
struct ChangesModelHardeningTests {
    @Test("a hunk from an outdated diff is refused instead of staging something else")
    func staleHunk() async throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", original)
        fixture.sandbox.write("f.txt", edited)
        let model = try await openRepository(fixture)
        let changes = model.changes
        await changes.select(ChangeSelection(path: "f.txt", staged: false))
        let oldDiff = try #require(changes.diff)
        let oldHunk = try #require(oldDiff.index.hunks.first)
        try await changes.stage(["f.txt"]) // the whole file goes in; the diff on screen is now outdated

        await #expect(throws: (any Error).self) { try await changes.applyHunk(oldHunk, of: oldDiff) }

        #expect(model.status.unstaged.isEmpty)
        #expect(try fixture.git.run(["diff", "--cached", "--stat"]).text.contains("f.txt"))
    }

    @Test("hunk buttons are only offered for the diff of the current selection")
    func diffSelection() async throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", original)
        fixture.sandbox.write("f.txt", edited)
        let model = try await openRepository(fixture)
        let changes = model.changes

        await changes.select(ChangeSelection(path: "f.txt", staged: false))

        #expect(changes.diffSelection == ChangeSelection(path: "f.txt", staged: false))
        changes.selection = ChangeSelection(path: "f.txt", staged: true) // selection moved, the diff has not caught up
        #expect(changes.diffSelection != changes.selection)
    }

    @Test("amend turned on and off quickly does not leave the old message behind")
    func amendRace() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "previous message")
        let model = try await openRepository(fixture)
        let changes = model.changes

        let turningOn = Task { await changes.setAmend(true) }
        await Task.yield() // let it start and reach the point where it waits for the last message
        #expect(changes.amend)
        await changes.setAmend(false)
        await turningOn.value

        #expect(!changes.amend)
        #expect(changes.commitMessage.isEmpty)
    }

    @Test("quick successive stage actions all succeed (they never run at the same time)")
    func serialWrites() async throws {
        let fixture = try GitFixture()
        try fixture.commit("keep.txt", "1\n")
        for name in ["a", "b", "c", "d"] { fixture.sandbox.write("\(name).txt", "\(name)\n") }
        let model = try await openRepository(fixture)
        let changes = model.changes

        async let first: Void = changes.stage(["a.txt"])
        async let second: Void = changes.stage(["b.txt"])
        async let third: Void = changes.stage(["c.txt"])
        async let fourth: Void = changes.stage(["d.txt"])
        _ = try await (first, second, third, fourth)

        #expect(Set(model.status.staged.map(\.path)) == ["a.txt", "b.txt", "c.txt", "d.txt"])
    }

    @Test("unstaging a renamed file also clears the old path")
    func unstageRename() async throws {
        let fixture = try GitFixture()
        try fixture.commit("old.txt", "a\nb\nc\nd\n")
        try fixture.git.run(["mv", "old.txt", "new.txt"])
        let model = try await openRepository(fixture)
        let rename = try #require(model.status.staged.first { $0.path == "new.txt" })

        try await model.changes.unstage(rename)

        #expect(model.status.staged.isEmpty)
        #expect(model.status.entries.map(\.path).sorted() == ["new.txt", "old.txt"])
    }

    @Test("a refresh that changed nothing keeps the diff on screen; a manual reload replaces it")
    func diffKeptAcrossRefresh() async throws {
        let fixture = try GitFixture()
        try fixture.commit("f.txt", original)
        fixture.sandbox.write("f.txt", edited)
        let model = try await openRepository(fixture)
        await model.changes.select(ChangeSelection(path: "f.txt", staged: false))
        let before = try #require(model.changes.diff)

        await model.refresh()
        #expect(model.changes.diff === before)
        await model.refresh(reloadDiffs: true)

        #expect(model.changes.diff !== before)
        #expect(model.changes.diff?.index.hunks.count == 2)
    }

    @Test("many refreshes at once end in a consistent, idle state")
    func overlappingRefreshes() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let model = try await openRepository(fixture)
        fixture.sandbox.write("a.txt", "2\n")

        let refreshes = (0..<6).map { _ in Task { await model.refresh() } }
        for refresh in refreshes { await refresh.value }

        #expect(model.status.unstaged.map(\.path) == ["a.txt"])
        #expect(!model.isLoading)
    }
}

@MainActor
@Suite("History model")
struct HistoryModelTests {
    @Test("the first page of commits and its graph rows")
    func firstPage() async throws {
        let fixture = try GitFixture()
        for n in 1...5 { try fixture.commit("a.txt", "\(n)\n", message: "c\(n)") }
        let model = try await openRepository(fixture)

        await model.history.reload()

        #expect(model.history.commits.map(\.subject) == ["c5", "c4", "c3", "c2", "c1"])
        #expect(model.history.graph.rows.count == 5)
        #expect(!model.history.hasMore)
    }

    @Test("more commits are appended page by page and the graph keeps its layout")
    func paging() async throws {
        let fixture = try GitFixture()
        for n in 1...7 { try fixture.commit("a.txt", "\(n)\n", message: "c\(n)") }
        let model = try await openRepository(fixture)
        let history = model.history
        history.pageSize = 3

        await history.reload()
        #expect(history.commits.count == 3)
        #expect(history.hasMore)
        await history.loadMore()
        await history.loadMore()

        #expect(history.commits.map(\.subject) == ["c7", "c6", "c5", "c4", "c3", "c2", "c1"])
        #expect(history.graph.rows.count == 7)
        #expect(!history.hasMore)
    }

    @Test("selecting a commit lists its files, and a file loads its diff")
    func detail() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        try fixture.commit("a.txt", "1\n2\n", message: "add line")
        sandboxWrite(fixture, "b.txt", "new\n")
        try fixture.commitAll("add b")
        let model = try await openRepository(fixture)
        let history = model.history
        await history.reload()

        let commit = try #require(history.commits.first { $0.subject == "add line" })
        await history.select(commit.id)
        #expect(history.files.map(\.path) == ["a.txt"])
        #expect(history.selectedFile == "a.txt") // the first file is shown straight away
        #expect(history.diff?.index.hunks.count == 1)

        await history.select(try #require(history.commits.first { $0.subject == "add b" }).id)
        #expect(history.files.map(\.path) == ["b.txt"])
    }

    @Test("showing all branches adds the commits of other branches")
    func allBranches() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "on main")
        try fixture.git.run(["checkout", "-q", "-b", "side"])
        try fixture.commit("b.txt", "1\n", message: "on side")
        try fixture.git.run(["checkout", "-q", "main"])
        let model = try await openRepository(fixture)
        let history = model.history
        await history.reload()
        #expect(history.commits.count == 1)

        history.allBranches = true
        await history.reload()

        #expect(history.commits.map(\.subject).sorted() == ["on main", "on side"])
    }

    @Test("a reload that starts while a page is loading still ends with the full history")
    func overlappingReloads() async throws {
        let fixture = try GitFixture()
        for n in 1...6 { try fixture.commit("a.txt", "\(n)\n", message: "c\(n)") }
        let model = try await openRepository(fixture)
        let history = model.history

        async let first: Void = history.reload()
        async let second: Void = history.reload()
        _ = await (first, second)

        #expect(history.commits.map(\.subject) == ["c6", "c5", "c4", "c3", "c2", "c1"])
        #expect(history.graph.rows.count == 6)
    }

    @Test("an empty repository has an empty history")
    func empty() async throws {
        let fixture = try GitFixture()
        let model = try await openRepository(fixture)

        await model.history.reload()

        #expect(model.history.commits.isEmpty)
        #expect(!model.history.hasMore)
    }
}

private func sandboxWrite(_ fixture: GitFixture, _ path: String, _ text: String) {
    fixture.sandbox.write(path, text)
}
