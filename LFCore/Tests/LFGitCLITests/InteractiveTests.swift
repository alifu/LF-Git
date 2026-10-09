import Foundation
@testable import LFGitCLI
import LFKit
import LFTestSupport
import Testing

private let twoConflicts = text(
    "head",
    "<<<<<<< HEAD", "1-ours", "=======", "1-theirs", ">>>>>>> feature",
    "middle",
    "<<<<<<< HEAD", "2-ours", "=======", "2-theirs", ">>>>>>> feature",
    "tail"
)

private let diff3One = text(
    "<<<<<<< HEAD", "ours", "||||||| base", "ancestor", "=======", "theirs", ">>>>>>> feature"
)

@Suite("lfgit tui")
struct InteractiveTests {
    private func run(_ source: String, inputs: [String], palette: TerminalPalette? = nil,
                     editor: @escaping ([UInt8]) -> [UInt8]? = { _ in nil }) throws -> (code: Int32, file: String, console: BufferConsole) {
        let box = Sandbox()
        let path = box.write("a.txt", source)
        let console = BufferConsole(inputs: inputs, palette: palette)
        let code = try InteractiveCommand.parse([path]).execute(console: console, editor: editor)
        return (code, box.readText(path), console)
    }

    @Test("c and i resolve each conflict in turn")
    func currentThenIncoming() throws {
        let result = try run(twoConflicts, inputs: ["c", "i"])

        #expect(result.code == 0)
        #expect(result.file == text("head", "1-ours", "middle", "2-theirs", "tail"))
        #expect(result.console.output.contains("2 resolved"))
    }

    @Test("b keeps both sides current first and B keeps incoming first")
    func bothOrders() throws {
        let result = try run(twoConflicts, inputs: ["b", "B"])

        #expect(result.file == text("head", "1-ours", "1-theirs", "middle", "2-theirs", "2-ours", "tail"))
    }

    @Test("a restores the base when the conflict has one")
    func ancestor() throws {
        let result = try run(diff3One, inputs: ["a"])

        #expect(result.code == 0)
        #expect(result.file == text("ancestor"))
    }

    @Test("a is refused when there is no base, and the prompt repeats")
    func ancestorRefused() throws {
        let result = try run(twoConflicts, inputs: ["a", "c", "c"])

        #expect(result.code == 0)
        #expect(result.console.errors.contains("no base"))
    }

    @Test("unknown keys are rejected and the prompt repeats")
    func unknownKey() throws {
        let result = try run(twoConflicts, inputs: ["zzz", "", "c", "c"])

        #expect(result.code == 0)
        #expect(result.file == text("head", "1-ours", "middle", "2-ours", "tail"))
        #expect(result.console.errors.contains("zzz"))
    }

    @Test("q saves the progress so far, keeps the rest verbatim and fails")
    func quitKeepsProgress() throws {
        let result = try run(twoConflicts, inputs: ["i", "q"])

        #expect(result.code == 1)
        #expect(result.file == text(
            "head", "1-theirs", "middle", "<<<<<<< HEAD", "2-ours", "=======", "2-theirs", ">>>>>>> feature", "tail"
        ))
        #expect(result.console.output.contains("1 unresolved"))
    }

    @Test("k leaves a conflict unresolved and moves on")
    func keepUnresolved() throws {
        let result = try run(twoConflicts, inputs: ["k", "c"])

        #expect(result.code == 1)
        #expect(result.file.contains("<<<<<<< HEAD\n1-ours"))
        #expect(result.file.contains("2-ours"))
        #expect(!result.file.contains("2-theirs"))
    }

    @Test("running out of input behaves like quit and writes nothing when nothing was decided")
    func endOfInput() throws {
        let result = try run(twoConflicts, inputs: [])

        #expect(result.code == 1)
        #expect(result.file == twoConflicts)
    }

    @Test("e opens the editor with both sides and uses what comes back")
    func edit() throws {
        let captured = EditorProbe()
        let result = try run(diff3One, inputs: ["e"]) { initial in
            captured.received = String(decoding: initial, as: UTF8.self)
            return Array(text("hand merged").utf8)
        }

        #expect(result.code == 0)
        #expect(captured.received == text("ours", "theirs"))
        #expect(result.file == text("hand merged"))
    }

    @Test("a cancelled edit leaves the conflict open")
    func editCancelled() throws {
        let result = try run(diff3One, inputs: ["e", "q"]) { _ in nil }

        #expect(result.code == 1)
        #expect(result.file == diff3One)
    }

    @Test("the conflict is shown with labelled sides, line numbers and its position")
    func rendering() throws {
        let result = try run(twoConflicts, inputs: ["c", "c"])

        #expect(result.console.output.contains("conflict 1 of 2"))
        #expect(result.console.output.contains("a.txt:2"))
        #expect(result.console.output.contains("Current"))
        #expect(result.console.output.contains("HEAD"))
        #expect(result.console.output.contains("Incoming"))
        #expect(result.console.output.contains("feature"))
        #expect(result.console.output.contains("1-ours"))
    }

    @Test("colour escapes appear only when a palette is set")
    func colours() throws {
        let plain = try run(twoConflicts, inputs: ["c", "c"], palette: nil)
        let coloured = try run(twoConflicts, inputs: ["c", "c"], palette: .dark)

        #expect(!plain.console.output.contains("\u{1B}["))
        #expect(coloured.console.output.contains("\u{1B}[38;2;"))
    }

    @Test("very long sides are truncated with a count of the hidden lines")
    func truncation() throws {
        let many = (1...40).map { "ours \($0)" }
        let source = (["<<<<<<< HEAD"] + many + ["=======", "theirs", ">>>>>>> feature"]).joined(separator: "\n") + "\n"

        let result = try run(source, inputs: ["c"])

        #expect(result.console.output.contains("more line"))
        #expect(!result.console.output.contains("ours 40"))
        #expect(result.file == many.joined(separator: "\n") + "\n")
    }

    @Test("a file without conflicts is left alone")
    func noConflicts() throws {
        let result = try run("hello\n", inputs: [])

        #expect(result.code == 0)
        #expect(result.console.output.contains("no conflict markers"))
    }

    @Test("a binary file is refused with a hint")
    func binaryRefused() throws {
        let box = Sandbox()
        let path = box.write("a.bin", bytes: [0, 1, 2])
        let console = BufferConsole()

        let code = try InteractiveCommand.parse([path]).execute(console: console, editor: { _ in nil })

        #expect(code == 1)
        #expect(console.errors.contains("binary"))
    }
}

final class EditorProbe: @unchecked Sendable {
    var received = ""
}

@Suite("lfgit mergetool")
struct MergetoolTests {
    @Test("resolves the MERGED file and reports success")
    func resolves() throws {
        let box = Sandbox()
        let merged = box.write("MERGED.txt", twoConflicts)
        let other = box.write("other.txt", "")
        let console = BufferConsole(inputs: ["c", "b"])

        let code = try MergetoolCommand.parse([other, other, other, merged]).execute(console: console, editor: { _ in nil })

        #expect(code == 0)
        #expect(box.readText(merged) == text("head", "1-ours", "middle", "2-ours", "2-theirs", "tail"))
    }

    @Test("exits non-zero while conflicts remain so git knows the merge is not done")
    func incomplete() throws {
        let box = Sandbox()
        let merged = box.write("MERGED.txt", twoConflicts)
        let other = box.write("other.txt", "")
        let console = BufferConsole(inputs: ["c", "q"])

        let code = try MergetoolCommand.parse([other, other, other, merged]).execute(console: console, editor: { _ in nil })

        #expect(code == 1)
    }
}
