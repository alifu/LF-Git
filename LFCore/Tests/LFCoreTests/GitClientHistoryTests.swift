import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git branches")
struct GitBranchTests {
    @Test("local branches are listed with the current one marked")
    func list() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        try fixture.git.run(["branch", "feature"])

        let branches = try GitClient(directory: fixture.directory).branches()

        #expect(branches.map(\.name).sorted() == ["feature", "main"])
        #expect(branches.first { $0.isCurrent }?.name == "main")
        #expect(branches.allSatisfy { !$0.isRemote })
    }

    @Test("a branch knows how far it is ahead of and behind its upstream")
    func aheadBehind() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        _ = try fixture.addOrigin()
        let client = GitClient(directory: fixture.directory)
        try fixture.git.run(["push", "-u", "origin", "main"])
        let level = try #require(try client.branches().first { $0.name == "main" && !$0.isRemote })
        #expect(level.ahead == 0)
        #expect(level.behind == 0)

        try fixture.commit("b.txt", "2\n")
        try fixture.commit("c.txt", "3\n")
        let main = try #require(try client.branches().first { $0.name == "main" && !$0.isRemote })
        #expect(main.ahead == 2)
        #expect(main.behind == 0)

        try fixture.git.run(["push", "origin", "main"])
        try fixture.git.run(["reset", "--hard", "HEAD~2"])
        let behind = try #require(try client.branches().first { $0.name == "main" && !$0.isRemote })
        #expect(behind.ahead == 0)
        #expect(behind.behind == 2)
    }

    @Test("create, switch and delete")
    func lifecycle() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)

        try client.createBranch("topic")
        #expect(try client.status().branch == "topic")
        try client.switchBranch("main")
        #expect(try client.status().branch == "main")
        try client.deleteBranch("topic")

        #expect(try client.branches().map(\.name) == ["main"])
    }

    @Test("deleting an unmerged branch is refused unless forced")
    func unmerged() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let client = GitClient(directory: fixture.directory)
        try client.createBranch("topic")
        try fixture.commit("b.txt", "work\n")
        try client.switchBranch("main")

        #expect(throws: GitError.self) { try client.deleteBranch("topic") }
        try client.deleteBranch("topic", force: true)
        #expect(try client.branches().map(\.name) == ["main"])
    }

    @Test("a new branch can start from another commit")
    func startPoint() throws {
        let fixture = try GitFixture()
        let first = try fixture.commit("a.txt", "1\n")
        try fixture.commit("a.txt", "2\n")
        let client = GitClient(directory: fixture.directory)

        try client.createBranch("old", from: first)

        #expect(try fixture.git.run(["rev-parse", "HEAD"]).text == first)
    }

    @Test("remote branches are listed, and switching to one creates a tracking branch")
    func remote() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let origin = try fixture.addOrigin()
        try fixture.git.run(["push", "-q", "origin", "main:release"])
        let other = try GitFixture(cloning: origin)
        let client = GitClient(directory: other.directory)

        let remotes = try client.branches().filter(\.isRemote).map(\.name)
        try client.switchBranch("origin/release")

        #expect(remotes.contains("origin/release"))
        #expect(!remotes.contains("origin/HEAD"))
        let status = try client.status()
        #expect(status.branch == "release")
        #expect(status.upstream == "origin/release")
    }

    @Test("a branch name that git refuses is reported, not swallowed")
    func invalidName() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")

        #expect(throws: GitError.self) { try GitClient(directory: fixture.directory).createBranch("bad name with spaces") }
    }
}

@Suite("Git history")
struct GitHistoryTests {
    @Test("commits come newest first with their parents, author, date and subject")
    func log() throws {
        let fixture = try GitFixture()
        let first = try fixture.commit("a.txt", "1\n", message: "first")
        let second = try fixture.commit("a.txt", "2\n", message: "second\n\nlong body")

        let commits = try GitClient(directory: fixture.directory).log()

        #expect(commits.map(\.subject) == ["second", "first"])
        #expect(commits[0].hash == second)
        #expect(commits[0].parents == [first])
        #expect(commits[1].parents.isEmpty)
        #expect(commits[0].authorName == "Test")
        #expect(commits[0].authorEmail == "test@example.com")
        #expect(abs(commits[0].date.timeIntervalSinceNow) < 120)
        #expect(commits[0].shortHash == String(second.prefix(7)))
    }

    @Test("branch and tag names decorate their commits")
    func refs() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        try fixture.git.run(["tag", "v1"])
        try fixture.git.run(["branch", "feature"])

        let refs = try GitClient(directory: fixture.directory).log().first?.refs ?? []

        #expect(refs.contains("main"))
        #expect(refs.contains("feature"))
        #expect(refs.contains("tag: v1"))
        #expect(refs.contains("HEAD -> main") == false) // shown as the plain branch name
    }

    @Test("paging with skip and maxCount, and --all includes other branches")
    func paging() throws {
        let fixture = try GitFixture()
        for n in 1...5 { try fixture.commit("a.txt", "\(n)\n", message: "c\(n)") }
        try fixture.git.run(["checkout", "-q", "-b", "side", "HEAD~2"])
        try fixture.commit("b.txt", "x\n", message: "side commit")
        try fixture.git.run(["checkout", "-q", "main"])
        let client = GitClient(directory: fixture.directory)

        #expect(try client.log(maxCount: 2).map(\.subject) == ["c5", "c4"])
        #expect(try client.log(maxCount: 2, skip: 2).map(\.subject) == ["c3", "c2"])
        #expect(try client.log().count == 5)
        #expect(try client.log(allBranches: true).count == 6)
    }

    @Test("a repository without commits has an empty history")
    func empty() throws {
        let fixture = try GitFixture()

        #expect(try GitClient(directory: fixture.directory).log().isEmpty)
    }

    @Test("a commit's subject can contain unusual characters")
    func unusualSubject() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "fix: \"quotes\", tabs\tand émojis 🎉 | pipes")

        let subject = try GitClient(directory: fixture.directory).log().first?.subject

        #expect(subject == "fix: \"quotes\", tabs\tand émojis 🎉 | pipes")
    }

    @Test("changed files of a normal, root, renamed and merge commit")
    func changedFiles() throws {
        let fixture = try GitFixture()
        let root = try fixture.commit("a.txt", "1\nsecond\nthird\nfourth\n", message: "root")
        try fixture.git.run(["mv", "a.txt", "b.txt"])
        try fixture.commitAll("rename")
        let renamed = try fixture.git.run(["rev-parse", "HEAD"]).text
        try fixture.git.run(["checkout", "-q", "-b", "side", root])
        try fixture.commit("side.txt", "s\n", message: "side")
        try fixture.git.run(["checkout", "-q", "main"])
        try fixture.git.run(["merge", "-q", "--no-ff", "-m", "merge side", "side"])
        let client = GitClient(directory: fixture.directory)
        let commits = try client.log()

        let merge = try client.changedFiles(in: commits[0])
        let rename = try client.changedFiles(in: try #require(commits.first { $0.hash == renamed }))
        let rootFiles = try client.changedFiles(in: try #require(commits.first { $0.hash == root }))

        #expect(merge.map(\.path) == ["side.txt"]) // against the first parent
        #expect(merge.first?.status == .added)
        #expect(rename.first?.status == .renamed)
        #expect(rename.first?.path == "b.txt")
        #expect(rename.first?.originalPath == "a.txt")
        #expect(rootFiles.map(\.path) == ["a.txt"])
    }

    @Test("the diff of one file in a commit, including a root commit")
    func commitDiff() throws {
        let fixture = try GitFixture()
        let root = try fixture.commit("a.txt", "1\n", message: "root")
        let second = try fixture.commit("a.txt", "1\n2\n", message: "second")
        let client = GitClient(directory: fixture.directory)
        let commits = try client.log()

        let secondDiff = try client.diff(of: .commit(try #require(commits.first { $0.hash == second }), path: "a.txt"))
        let rootDiff = try client.diff(of: .commit(try #require(commits.first { $0.hash == root }), path: "a.txt"))

        #expect((1...secondDiff.lineCount).map { secondDiff.text(ofLine: $0) }.contains("+2"))
        #expect((1...rootDiff.lineCount).map { rootDiff.text(ofLine: $0) }.contains("+1"))
    }
}

@Suite("Commit graph")
struct CommitGraphTests {
    private func commit(_ hash: String, _ parents: [String]) -> GitCommit {
        GitCommit(hash: hash, parents: parents, authorName: "a", authorEmail: "a@x", date: .distantPast, refs: [], subject: hash)
    }

    @Test("a linear history stays in one lane")
    func linear() {
        var graph = CommitGraph()
        graph.append([commit("c", ["b"]), commit("b", ["a"]), commit("a", [])])

        #expect(graph.rows.map(\.lane) == [0, 0, 0])
        #expect(graph.rows.map(\.laneCount) == [1, 1, 1])
        #expect(graph.rows[0].continuesDown && graph.rows[1].continuesDown && !graph.rows[2].continuesDown)
        #expect(!graph.rows[0].hasLineAbove && graph.rows[1].hasLineAbove)
    }

    @Test("a merge opens a lane for the second parent, which closes where the branch started")
    func mergeShape() {
        // m merges side (s) into main (b); both come from a.
        var graph = CommitGraph()
        graph.append([commit("m", ["b", "s"]), commit("b", ["a"]), commit("s", ["a"]), commit("a", [])])

        #expect(graph.rows[0].lane == 0)
        #expect(graph.rows[0].branchedLanes == [1]) // the merge commit starts a line towards the second parent
        #expect(graph.rows[1].lane == 0)
        #expect(graph.rows[1].passingLanes == [1]) // the side lane runs past b
        #expect(graph.rows[2].lane == 1)
        #expect(graph.rows[3].lane == 0)
        #expect(graph.rows[3].mergedLanes == [1]) // the side lane joins at the common ancestor
        #expect(graph.rows[3].laneCount == 2)
    }

    @Test("two branch tips in the same graph get separate lanes")
    func twoTips() {
        var graph = CommitGraph()
        graph.append([commit("x", ["a"]), commit("y", ["a"]), commit("a", [])])

        #expect(graph.rows[0].lane == 0)
        #expect(graph.rows[1].lane == 1)
        #expect(graph.rows[2].lane == 0)
        #expect(graph.rows[2].mergedLanes == [1])
    }

    @Test("appending in pages gives the same layout as one call")
    func paged() {
        let commits = [commit("m", ["b", "s"]), commit("b", ["a"]), commit("s", ["a"]), commit("a", [])]
        var whole = CommitGraph()
        whole.append(commits)
        var paged = CommitGraph()
        paged.append(Array(commits[..<2]))
        paged.append(Array(commits[2...]))

        #expect(paged.rows == whole.rows)
    }
}
