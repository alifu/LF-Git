import Foundation
import LFKit
import LFTestSupport
import Testing
@testable import LF_Git

private let twoConflicts = text(
    "head",
    "<<<<<<< HEAD", "1-ours", "=======", "1-theirs", ">>>>>>> feature",
    "middle",
    "<<<<<<< HEAD", "2-ours", "||||||| base", "2-base", "=======", "2-theirs", ">>>>>>> feature",
    "tail"
)

@MainActor
private func editor(_ source: String, in box: Sandbox, name: String = "a.txt") async throws -> EditorModel {
    let path = box.write(name, source)
    return try await EditorModel.load(path: path, displayPath: name, repository: nil)
}

@MainActor
@Suite("Editor model")
struct EditorModelTests {
    @Test("loading exposes lines, conflict spans and line text")
    func loads() async throws {
        let box = Sandbox()
        let model = try await editor(twoConflicts, in: box)

        #expect(model.lineCount == 15)
        #expect(model.spans.count == 2)
        #expect(model.spans[1] == ConflictSpan(index: 1, openLine: 8, baseLine: 10, separatorLine: 12, closeLine: 14))
        #expect(model.text(ofLine: 3) == "1-ours")
        #expect(model.role(ofLine: 13) == .incoming(conflict: 1))
        #expect(model.unresolvedCount == 2)
        #expect(model.hasBase(1) && !model.hasBase(0))
    }

    @Test("resolving, undoing and redoing")
    func undoRedo() async throws {
        let box = Sandbox()
        let model = try await editor(twoConflicts, in: box)

        model.resolve(0, as: .incoming)
        model.resolve(1, as: .current)
        #expect(model.unresolvedCount == 0)
        #expect(model.choice(of: 0) == .incoming)

        model.undo()
        #expect(model.choice(of: 1) == .unresolved)
        #expect(model.canRedo)
        model.redo()
        #expect(model.choice(of: 1) == .current)

        model.resolve(0, as: .bothCurrentFirst)
        #expect(!model.canRedo) // a new action clears the redo stack
    }

    @Test("accept-all is a single undo step")
    func acceptAll() async throws {
        let box = Sandbox()
        let model = try await editor(twoConflicts, in: box)

        model.resolveAll(as: .incoming)
        #expect(model.unresolvedCount == 0)
        model.undo()
        #expect(model.unresolvedCount == 2)
    }

    @Test("next and previous move between conflicts, preferring unresolved ones, and wrap")
    func navigation() async throws {
        let box = Sandbox()
        let model = try await editor(twoConflicts, in: box)

        model.focusNext()
        #expect(model.focusedConflict == 0)
        model.focusNext()
        #expect(model.focusedConflict == 1)
        model.focusNext()
        #expect(model.focusedConflict == 0)
        model.resolve(1, as: .current)
        model.focusNext()
        #expect(model.focusedConflict == 0) // the only unresolved one
        model.focusPrevious()
        #expect(model.focusedConflict == 0)
    }

    @Test("the side texts of a conflict are available for comparing")
    func sides() async throws {
        let box = Sandbox()
        let model = try await editor(twoConflicts, in: box)

        let sides = model.sides(of: 1)

        #expect(sides.current == "2-ours\n")
        #expect(sides.base == "2-base\n")
        #expect(sides.incoming == "2-theirs\n")
        #expect(sides.currentLabel == "HEAD")
        #expect(sides.incomingLabel == "feature")
    }

    @Test("saving writes the resolution; partial progress keeps the open conflicts")
    func save() async throws {
        let box = Sandbox()
        let model = try await editor(twoConflicts, in: box)

        model.resolve(0, as: .current)
        #expect(model.hasUnsavedChanges)
        try await model.save()

        #expect(!model.hasUnsavedChanges)
        let saved = box.readText(box.path("a.txt"))
        #expect(saved.hasPrefix(text("head", "1-ours", "middle", "<<<<<<< HEAD")))
    }

    @Test("saving twice in a row works")
    func saveTwice() async throws {
        let box = Sandbox()
        let model = try await editor(twoConflicts, in: box)

        model.resolve(0, as: .current)
        try await model.save()
        model.resolve(1, as: .incoming)
        try await model.save()

        #expect(box.readText(box.path("a.txt")) == text("head", "1-ours", "middle", "2-theirs", "tail"))
    }

    @Test("a huge line is cut before it is decoded")
    func hugeLine() async throws {
        let box = Sandbox()
        let model = try await editor(String(repeating: "é", count: 200_000) + "\n", in: box)

        let shown = model.text(ofLine: 1)

        #expect(shown.count <= EditorModel.maxDisplayedColumns + 1)
        #expect(shown.hasSuffix("…"))
        #expect(!shown.contains("\u{FFFD}"))
    }

    @Test("navigation asks the editor to scroll; a click that only focuses does not")
    func scrollRequests() async throws {
        let box = Sandbox()
        let model = try await editor(twoConflicts, in: box)
        let before = model.scrollRequest

        model.focusNext()
        #expect(model.scrollRequest != before)
        let afterNavigation = model.scrollRequest
        model.focusedConflict = 1
        #expect(model.scrollRequest == afterNavigation)
        model.jump(to: 1)
        #expect(model.scrollRequest != afterNavigation)
    }

    @Test("a fully resolved file is staged on save when it belongs to a repository")
    func saveStages() async throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        let model = try await EditorModel.load(
            path: fixture.sandbox.path("a.txt"), displayPath: "a.txt", repository: fixture.directory
        )

        model.resolveAll(as: .incoming)
        try await model.save()

        #expect(fixture.read("a.txt") == "a\nb-theirs\nc\n")
        #expect(try fixture.conflictedPaths().isEmpty)
    }

    @Test("an external change makes save fail instead of overwriting it")
    func externalChange() async throws {
        let box = Sandbox()
        let model = try await editor(twoConflicts, in: box)
        model.resolveAll(as: .current)
        box.write("a.txt", "someone else\n")

        await #expect(throws: LFError.self) { try await model.save() }
        #expect(box.readText(box.path("a.txt")) == "someone else\n")
    }

    @Test("a missing or binary file fails to load")
    func loadFailures() async {
        let box = Sandbox()
        let binary = box.write("b.bin", bytes: [0, 1, 2])

        await #expect(throws: (any Error).self) { _ = try await EditorModel.load(path: binary, displayPath: "b.bin", repository: nil) }
        await #expect(throws: (any Error).self) {
            _ = try await EditorModel.load(path: box.path("missing"), displayPath: "missing", repository: nil)
        }
    }
}

@MainActor
@Suite("Repository model")
struct RepositoryModelTests {
    @Test("lists conflicted files with kind and conflict count, and selects the first")
    func lists() async throws {
        let fixture = try GitFixture()
        let project = ClassicProject.withSources([1])
        var ours = project
        ours.addSource(2)
        var theirs = project
        theirs.addSource(3)
        try fixture.makeConflicts([
            .text("a.txt"),
            ConflictSpec(path: "logo.png", base: [0, 1, 2], ours: [0, 1, 3], theirs: [0, 1, 4]),
            ConflictSpec(path: "App.xcodeproj/project.pbxproj", base: project.bytes, ours: ours.bytes, theirs: theirs.bytes),
        ])
        let model = try RepositoryModel.open(at: fixture.directory)

        await model.refresh()

        let byPath = Dictionary(uniqueKeysWithValues: model.files.map { ($0.path, $0) })
        #expect(byPath["a.txt"]?.kind == .text)
        #expect(byPath["a.txt"]?.conflictCount == 1)
        #expect(byPath["logo.png"]?.kind == .binary)
        #expect(byPath["App.xcodeproj/project.pbxproj"]?.kind == .project)
        #expect(model.selection != nil)
    }

    @Test("an editor is kept per file, so switching files keeps unsaved resolutions")
    func editorsAreKept() async throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt"), .text("b.txt")])
        let model = try RepositoryModel.open(at: fixture.directory)
        await model.refresh()

        let first = try await model.editor(for: "a.txt")
        first.resolve(0, as: .incoming)
        _ = try await model.editor(for: "b.txt")
        let again = try await model.editor(for: "a.txt")

        #expect(first === again)
        #expect(again.choice(of: 0) == .incoming)
        #expect(model.hasUnsavedChanges)
        await model.refresh()
        #expect(try await model.editor(for: "a.txt") === first) // a reload keeps unsaved work
    }

    @Test("a file without markers can be marked resolved, which stages it")
    func markResolved() async throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([.text("a.txt")])
        fixture.sandbox.write("a.txt", "fixed by hand\n")
        let model = try RepositoryModel.open(at: fixture.directory)
        await model.refresh()

        try await model.markResolved("a.txt")

        #expect(try fixture.conflictedPaths().isEmpty)
        #expect(model.files.isEmpty)
    }

    @Test("re-merging a project file replaces its cached editor")
    func remergeDropsEditor() async throws {
        let fixture = try GitFixture()
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.addSource(2)
        ours.debugSettings["SWIFT_VERSION"] = .value("5.9")
        var theirs = base
        theirs.addSource(3)
        theirs.debugSettings["SWIFT_VERSION"] = .value("6.0")
        let path = "App.xcodeproj/project.pbxproj"
        try fixture.makeConflicts([ConflictSpec(path: path, base: base.bytes, ours: ours.bytes, theirs: theirs.bytes)])
        let model = try RepositoryModel.open(at: fixture.directory)
        await model.refresh()
        let before = try await model.editor(for: path)

        _ = try await model.remergeProject(path)

        let after = try await model.editor(for: path)
        #expect(before !== after)
        #expect(after.conflictCount == 1)
    }

    @Test("opening a plain folder fails with a clear error")
    func notARepository() {
        let box = Sandbox()

        #expect(throws: (any Error).self) { try RepositoryModel.open(at: box.root) }
    }

    @Test("a binary file can take one side, which stages it")
    func binaryTakeSide() async throws {
        let fixture = try GitFixture()
        try fixture.makeConflicts([ConflictSpec(path: "logo.png", base: [0, 1, 2], ours: [0, 1, 3], theirs: [0, 1, 4])])
        let model = try RepositoryModel.open(at: fixture.directory)
        await model.refresh()

        try await model.takeSide(.theirs, of: "logo.png")

        #expect(fixture.sandbox.read(fixture.sandbox.path("logo.png")) == [0, 1, 4])
        #expect(try fixture.conflictedPaths().isEmpty)
        #expect(model.files.isEmpty)
    }

    @Test("a project file can be re-merged object by object")
    func remerge() async throws {
        let fixture = try GitFixture()
        let base = ClassicProject.withSources([1])
        var ours = base
        ours.addSource(2)
        var theirs = base
        theirs.addSource(3)
        var expected = base
        expected.addSource(2)
        expected.addSource(3)
        try fixture.makeConflicts([ConflictSpec(path: "App.xcodeproj/project.pbxproj", base: base.bytes, ours: ours.bytes, theirs: theirs.bytes)])
        let model = try RepositoryModel.open(at: fixture.directory)
        await model.refresh()

        let outcome = try await model.remergeProject("App.xcodeproj/project.pbxproj")

        #expect(outcome.isClean)
        #expect(fixture.read("App.xcodeproj/project.pbxproj") == expected.text)
        #expect(model.files.isEmpty) // clean results are staged
    }
}
