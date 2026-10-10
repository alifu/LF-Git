import Foundation
import LFKit
import LFTestSupport
import Testing
@testable import LF_Git

@MainActor
@Suite("Editing a conflict by hand")
struct ConflictEditTests {
    private let source = "head\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> feature\ntail\n"

    private func load(_ source: String, in box: Sandbox) async throws -> EditorModel {
        try await EditorModel.load(path: box.write("a.txt", source), displayPath: "a.txt", repository: nil)
    }

    @Test("the Edit box starts with both sides, and the typed text is what gets saved")
    func editAndSave() async throws {
        let box = Sandbox()
        let model = try await load(source, in: box)
        #expect(model.initialEditText(of: 0) == "ours\ntheirs\n")

        model.edit(0, text: "ours\nmine\ntheirs\n")
        #expect(model.choice(of: 0) == .custom)
        #expect(model.unresolvedCount == 0)
        #expect(model.hasUnsavedChanges)
        try await model.save()

        #expect(box.readText(box.path("a.txt")) == "head\nours\nmine\ntheirs\ntail\n")
        #expect(!model.hasUnsavedChanges)
    }

    @Test("editing again changes the saved text, and undo brings the earlier text back")
    func undoRedo() async throws {
        let box = Sandbox()
        let model = try await load(source, in: box)
        model.edit(0, text: "first\n")
        try await model.save()

        model.edit(0, text: "second\n")
        #expect(model.hasUnsavedChanges, "the same choice with other text is still a change")

        model.undo()
        #expect(model.choice(of: 0) == .custom)
        #expect(!model.hasUnsavedChanges)
        model.undo()
        #expect(model.choice(of: 0) == .unresolved)
        model.redo()
        model.redo()
        try await model.save()
        #expect(box.readText(box.path("a.txt")) == "head\nsecond\ntail\n")
    }

    @Test("undoing an accepted side after an edit restores the edit, not the old side")
    func unresolveThenUndo() async throws {
        let box = Sandbox()
        let model = try await load(source, in: box)
        model.edit(0, text: "mine\n")
        model.resolve(0, as: .unresolved)
        #expect(model.initialEditText(of: 0) == "mine\n", "Edit reopens the last text")

        model.undo()
        #expect(model.choice(of: 0) == .custom)
        try await model.save()
        #expect(box.readText(box.path("a.txt")) == "head\nmine\ntail\n")
    }

    @Test("a Windows-style file keeps its line endings in the edited text")
    func crlf() async throws {
        let box = Sandbox()
        let model = try await load(source.replacingOccurrences(of: "\n", with: "\r\n"), in: box)

        model.edit(0, text: "one\ntwo\n")
        try await model.save()

        #expect(box.readText(box.path("a.txt")) == "head\r\none\r\ntwo\r\ntail\r\n")
    }

    @Test("an empty edit removes the conflict's lines entirely")
    func emptyEdit() async throws {
        let box = Sandbox()
        let model = try await load(source, in: box)
        model.edit(0, text: "")
        try await model.save()
        #expect(box.readText(box.path("a.txt")) == "head\ntail\n")
    }
}
