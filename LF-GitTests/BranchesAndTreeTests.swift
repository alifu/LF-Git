import AppKit
import Foundation
import LFKit
import LFTestSupport
import Testing
@testable import LF_Git

@Suite("Folder tree of paths")
struct PathTreeTests {
    private func build(_ paths: [String]) -> [PathNode<String>] {
        PathNode.build(paths, path: { $0 })
    }

    @Test("folders come first and files are sorted inside them")
    func grouping() {
        let tree = build(["b.txt", "src/z.swift", "a.txt", "src/a.swift", "docs/x.md"])

        #expect(tree.map(\.name) == ["docs", "src", "a.txt", "b.txt"])
        #expect(tree[1].children?.map(\.name) == ["a.swift", "z.swift"])
        #expect(tree[1].isFolder)
        #expect(!tree[2].isFolder)
    }

    @Test("a folder holding one folder is shown as a single row")
    func compressesNarrowChains() {
        let tree = build(["a/b/c/file.txt", "a/b/c/other.txt"])

        #expect(tree.count == 1)
        #expect(tree[0].name == "a/b/c")
        #expect(tree[0].children?.map(\.name) == ["file.txt", "other.txt"])
    }

    @Test("a folder with both files and folders is not compressed")
    func keepsBranchingFolders() {
        let tree = build(["a/one.txt", "a/b/two.txt"])

        #expect(tree.map(\.name) == ["a"])
        #expect(tree[0].children?.map(\.name) == ["b", "one.txt"])
    }

    @Test("every file below a folder is reachable, in list order, for staging the whole folder")
    func itemsOfFolder() {
        let tree = build(["src/a.swift", "src/sub/b.swift", "top.txt"])

        #expect(Set(tree[0].items) == ["src/a.swift", "src/sub/b.swift"])
        #expect(tree[1].items == ["top.txt"])
    }

    @Test("a folder knows how many items are below it without walking them")
    func itemCounts() {
        let tree = build(["src/a.swift", "src/sub/b.swift", "top.txt"])

        #expect(tree[0].itemCount == 2)
        #expect(tree[1].itemCount == 1)
    }

    @Test("a hundred thousand files in one folder build quickly")
    func hugeFolder() {
        let paths = (0..<100_000).map { "build/generated/file\($0).txt" }
        let started = ContinuousClock.now

        let tree = build(paths)

        #expect(tree.count == 1)
        #expect(tree[0].itemCount == 100_000)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test("folder ids are unique per level, so collapsing one leaves its namesake open")
    func uniqueIDs() {
        let tree = build(["a/x/1.txt", "a/x/2.txt", "b/x/1.txt", "b/x/2.txt"])
        let ids = tree.flatMap { [$0.id] + ($0.children ?? []).map(\.id) }

        #expect(Set(ids).count == ids.count)
    }
}

@MainActor
@Suite("Branches section")
struct BranchesSectionTests {
    private func open(_ fixture: GitFixture) async throws -> RepositoryModel {
        let model = try RepositoryModel.open(at: fixture.directory)
        await model.refresh()
        return model
    }

    @Test("showing another branch selects its newest commit, so the detail is never empty")
    func selectsNewestCommitOfEachBranch() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n", message: "on main")
        try fixture.git.run(["switch", "-c", "feature"])
        try fixture.commit("b.txt", "2\n", message: "on feature")
        let model = try await open(fixture)

        await model.branchHistory.show(.log(revision: "main"))
        #expect(model.branchHistory.selectedCommit?.subject == "on main")

        await model.branchHistory.show(.log(revision: "feature"))
        #expect(model.branchHistory.selectedCommit?.subject == "on feature")
        #expect(model.branchHistory.selectedFile == "b.txt")
        #expect(model.branchHistory.diff != nil)
    }

    @Test("blame arrives with the diff, keyed by line number")
    func blameBesideDiff() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "x\n", message: "one")
        try fixture.commit("a.txt", "x\ny\n", message: "two")
        let model = try await open(fixture)

        await model.history.reload()

        #expect(model.history.blameByLine[1]?.summary == "one")
        #expect(model.history.blameByLine[2]?.summary == "two")
        #expect(model.history.diff != nil)
    }

    @Test("a deleted file has a diff but no blame")
    func deletedFileHasNoBlame() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "x\n", message: "add")
        try fixture.git.run(["rm", "a.txt"])
        try fixture.git.run(["commit", "-m", "remove"])
        let model = try await open(fixture)

        await model.history.reload()

        #expect(model.history.diff != nil)
        #expect(model.history.blame == nil)
    }

    @Test("local branches carry how far they are from their upstream")
    func aheadBehind() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        _ = try fixture.addOrigin()
        try fixture.git.run(["push", "-u", "origin", "main"])
        try fixture.commit("b.txt", "2\n")
        let model = try await open(fixture)

        let main = try #require(model.branches.first { $0.name == "main" && !$0.isRemote })
        #expect(main.ahead == 1)
        #expect(main.behind == 0)
    }

    @Test("pulling with a rebase waits for a yes that names the branch and its upstream")
    func pullAsksFirst() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        _ = try fixture.addOrigin()
        try fixture.git.run(["push", "-u", "origin", "main"])
        let model = try await open(fixture)
        let app = AppModel()

        model.requestPull(.rebase, app: app)

        let question = try #require(model.confirmation)
        #expect(question.title.contains("main"))
        #expect(question.title.contains("origin/main"))
        #expect(question.title.lowercased().contains("rebase"))
    }

    @Test("a fast-forward pull needs no question")
    func fastForwardPullDoesNotAsk() async throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "1\n")
        let model = try await open(fixture)

        model.requestPull(.fastForwardOnly, app: AppModel())

        #expect(model.confirmation == nil)
    }
}

@Suite("Binary versions")
struct BinaryVersionTests {
    @Test("no data means this side deleted the file")
    func missing() {
        #expect(BinaryVersion.classify(nil).kind == .missing)
        #expect(BinaryVersion.classify(nil).summary == "This side deleted the file")
    }

    @Test("a PDF is recognised by its header")
    func pdf() {
        #expect(BinaryVersion.classify(Data("%PDF-1.7 rest".utf8)).kind == .pdf)
    }

    @Test("a decodable picture is an image, whatever its name")
    func image() throws {
        let image = NSImage(size: NSSize(width: 4, height: 3), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let version = BinaryVersion.classify(png)
        #expect(version.kind == .image)
        #expect(version.image != nil)
    }

    @Test("anything else has no preview but still reports its size")
    func other() {
        let version = BinaryVersion.classify(Data([0, 1, 2, 3]))
        #expect(version.kind == .other)
        #expect(version.byteCount == 4)
    }
}

@Suite("Copying diff lines")
struct DiffCopyTests {
    @Test("selected lines are copied as code, without the diff's +/- column or headers")
    @MainActor func copiesCode() throws {
        let fixture = try GitFixture()
        try fixture.commit("a.txt", "one\ntwo\n", message: "base")
        try "one\nTWO\nthree\n".write(to: fixture.directory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let diff = try GitClient(directory: fixture.directory).diff(of: .workingTree(path: "a.txt", staged: false))
        let coordinator = DiffTableView.Coordinator(diff: diff)

        let everything = coordinator.codeText(ofRows: IndexSet(integersIn: 0..<diff.lineCount))

        #expect(everything == "one\ntwo\nTWO\nthree")
    }
}
