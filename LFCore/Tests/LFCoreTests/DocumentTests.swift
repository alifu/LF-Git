import Foundation
import LFCore
import Testing
@testable import LFKit

private let simpleConflict = text(
    "before", "<<<<<<< HEAD", "ours1", "ours2", "=======", "theirs1", ">>>>>>> feature", "after"
)

private let diff3Conflict = text(
    "before", "<<<<<<< HEAD", "ours", "||||||| merged common ancestors", "base", "=======", "theirs",
    ">>>>>>> feature", "after"
)

private func openFailure(_ path: String, markerSize: Int = 7) -> LFError? {
    do {
        _ = try LFDocument(path: path, markerSize: markerSize)
        return nil
    } catch {
        return error
    }
}

@Suite("Scanning")
struct ScanTests {
    @Test("a file without markers has no conflicts and keeps its line count")
    func noConflicts() throws {
        let box = Sandbox()
        let doc = try LFDocument(path: box.write("a.txt", text("one", "two", "three")))

        #expect(doc.info.conflictCount == 0)
        #expect(doc.info.lineCount == 3)
        #expect(doc.info.eol == .lf)
        #expect(doc.info.encoding == .utf8)
    }

    @Test("an empty file opens with zero lines")
    func emptyFile() throws {
        let box = Sandbox()
        let doc = try LFDocument(path: box.write("empty.txt", ""))

        #expect(doc.info.size == 0)
        #expect(doc.info.lineCount == 0)
        #expect(doc.info.conflictCount == 0)
        #expect(doc.info.eol == .none)
    }

    @Test("a conflict reports its marker lines, labels and side contents")
    func conflictDetails() throws {
        let box = Sandbox()
        let doc = try LFDocument(path: box.write("a.txt", simpleConflict))

        let conflict = try doc.conflict(at: 0)

        #expect(doc.info.conflictCount == 1)
        #expect(conflict.openLine == 2)
        #expect(conflict.separatorLine == 5)
        #expect(conflict.closeLine == 7)
        #expect(conflict.hasBase == false)
        #expect(conflict.choice == .unresolved)
        #expect(String(decoding: doc.bytes(in: conflict.current), as: UTF8.self) == text("ours1", "ours2"))
        #expect(String(decoding: doc.bytes(in: conflict.incoming), as: UTF8.self) == text("theirs1"))
        #expect(String(decoding: doc.bytes(in: conflict.currentLabel), as: UTF8.self) == "HEAD")
        #expect(String(decoding: doc.bytes(in: conflict.incomingLabel), as: UTF8.self) == "feature")
        #expect(conflict.currentLineCount == 2)
        #expect(conflict.incomingLineCount == 1)
    }

    @Test("diff3 conflicts expose the base section")
    func diff3Base() throws {
        let box = Sandbox()
        let doc = try LFDocument(path: box.write("a.txt", diff3Conflict))

        let conflict = try doc.conflict(at: 0)

        #expect(conflict.hasBase)
        #expect(conflict.baseLine == 4)
        #expect(String(decoding: doc.bytes(in: conflict.base), as: UTF8.self) == text("base"))
    }

    @Test("separator and closing markers outside a conflict are plain content")
    func markersOutsideConflictAreContent() throws {
        let box = Sandbox()
        let source = text("Title", "=======", "|||||||", ">>>>>>> not a conflict", "end")
        let doc = try LFDocument(path: box.write("readme.md", source))

        #expect(doc.info.conflictCount == 0)
    }

    @Test("markers with a different length or a glued suffix are not markers")
    func lookalikeMarkers() throws {
        let box = Sandbox()
        let source = text("<<<<<<<< eight", "<<<<<<<glued", "======== eight", "  <<<<<<< indented", ">>>>>>>>")
        let doc = try LFDocument(path: box.write("a.txt", source))

        #expect(doc.info.conflictCount == 0)
    }

    @Test("a custom marker size is honoured")
    func customMarkerSize() throws {
        let box = Sandbox()
        let long = text(
            "<<<<<<<<<< HEAD", "ours", "==========", "theirs", ">>>>>>>>>> topic"
        )
        let path = box.write("a.txt", long)

        #expect(try LFDocument(path: path, markerSize: 10).info.conflictCount == 1)
        #expect(try LFDocument(path: path, markerSize: 7).info.conflictCount == 0)
    }

    @Test("a marker-looking line inside the incoming side stays content")
    func separatorInsideIncomingIsContent() throws {
        let box = Sandbox()
        let source = text("<<<<<<< a", "ours", "=======", "Heading", "=======", "|||||||", ">>>>>>> b")
        let doc = try LFDocument(path: box.write("a.md", source))

        let conflict = try doc.conflict(at: 0)

        #expect(doc.info.conflictCount == 1)
        #expect(String(decoding: doc.bytes(in: conflict.incoming), as: UTF8.self) == text("Heading", "=======", "|||||||"))
    }

    @Test("empty sides are allowed")
    func emptySides() throws {
        let box = Sandbox()
        let doc = try LFDocument(path: box.write("a.txt", text("<<<<<<< a", "=======", ">>>>>>> b")))

        let conflict = try doc.conflict(at: 0)

        #expect(conflict.current.length == 0)
        #expect(conflict.incoming.length == 0)
        #expect(conflict.currentLineCount == 0)
    }

    @Test("CRLF files are detected and the markers still match")
    func crlfDetected() throws {
        let box = Sandbox()
        let source = text("a", "<<<<<<< HEAD", "x", "=======", "y", ">>>>>>> b", "z", eol: "\r\n")
        let doc = try LFDocument(path: box.write("a.txt", source))

        #expect(doc.info.eol == .crlf)
        #expect(doc.info.conflictCount == 1)
    }

    @Test("mixed line endings are reported as mixed")
    func mixedEol() throws {
        let box = Sandbox()
        let doc = try LFDocument(path: box.write("a.txt", "a\r\nb\nc\n"))

        #expect(doc.info.eol == .mixed)
    }

    @Test("line offsets resolve through the sparse index", arguments: [1, 2, 1024, 1025, 2049, 5000])
    func lineOffsets(line: Int) throws {
        let box = Sandbox()
        let lines = (1...5000).map { "line \($0)" }
        let source = lines.joined(separator: "\n") + "\n"
        let doc = try LFDocument(path: box.write("big.txt", source))

        let offset = try doc.lineOffset(line)

        let expected = lines.prefix(line - 1).reduce(0) { $0 + $1.utf8.count + 1 }
        #expect(offset == expected)
        #expect(doc.info.lineCount == 5000)
    }

    @Test("line numbers outside the file are rejected")
    func lineOffsetOutOfRange() throws {
        let box = Sandbox()
        let doc = try LFDocument(path: box.write("a.txt", text("a", "b")))

        #expect(throws: LFError.self) { try doc.lineOffset(0) }
        #expect(throws: LFError.self) { try doc.lineOffset(4) }
        #expect(try doc.lineOffset(3) == 4)
    }
}

@Suite("Malformed input")
struct MalformedTests {
    @Test("end of file inside a conflict names the opening line")
    func unterminated() {
        let box = Sandbox()
        let path = box.write("a.txt", text("ok", "<<<<<<< HEAD", "ours", "=======", "theirs"))

        let error = openFailure(path)

        #expect(error?.status == LF_ERR_MALFORMED)
        #expect(error?.message.contains("line 2") == true)
    }

    @Test("a conflict start inside a conflict is rejected")
    func nested() {
        let box = Sandbox()
        let path = box.write("a.txt", text("<<<<<<< a", "x", "<<<<<<< b", "=======", ">>>>>>> c"))

        let error = openFailure(path)

        #expect(error?.status == LF_ERR_MALFORMED)
        #expect(error?.message.contains("line 3") == true)
    }

    @Test("a closing marker before the separator is rejected")
    func closeBeforeSeparator() {
        let box = Sandbox()
        let path = box.write("a.txt", text("<<<<<<< a", "x", ">>>>>>> b"))

        #expect(openFailure(path)?.status == LF_ERR_MALFORMED)
    }

    @Test("a missing file reports an I/O error with the path")
    func missingFile() {
        let error = openFailure("/nonexistent/lfgit/file.txt")

        #expect(error?.status == LF_ERR_IO)
        #expect(error?.message.contains("/nonexistent/lfgit/file.txt") == true)
    }

    @Test("a directory is rejected")
    func directory() {
        let box = Sandbox()

        #expect(openFailure(box.root.path)?.status == LF_ERR_INVALID_ARGUMENT)
    }

    @Test("binary files are unsupported")
    func binary() {
        let box = Sandbox()
        let path = box.write("img.bin", bytes: [0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02])

        #expect(openFailure(path)?.status == LF_ERR_UNSUPPORTED)
    }

    @Test("UTF-32 is treated as unsupported")
    func utf32() {
        let box = Sandbox()
        let path = box.write("u32.txt", bytes: [0xFF, 0xFE, 0x00, 0x00, 0x61, 0x00, 0x00, 0x00])

        #expect(openFailure(path)?.status == LF_ERR_UNSUPPORTED)
    }

    @Test("invalid UTF-16 is unsupported")
    func invalidUTF16() {
        let box = Sandbox()
        let path = box.write("bad16.txt", bytes: [0xFF, 0xFE, 0x00, 0xD8, 0x41, 0x00])

        #expect(openFailure(path)?.status == LF_ERR_UNSUPPORTED)
    }
}

@Suite("Resolving and saving")
struct ResolveTests {
    struct Case: Sendable {
        let choice: LFChoice
        let expected: String
    }

    static let simpleCases: [Case] = [
        Case(choice: .current, expected: text("before", "ours1", "ours2", "after")),
        Case(choice: .incoming, expected: text("before", "theirs1", "after")),
        Case(choice: .bothCurrentFirst, expected: text("before", "ours1", "ours2", "theirs1", "after")),
        Case(choice: .bothIncomingFirst, expected: text("before", "theirs1", "ours1", "ours2", "after")),
    ]

    @Test("each choice produces the expected file", arguments: simpleCases)
    func choices(testCase: Case) throws {
        let box = Sandbox()
        let path = box.write("a.txt", simpleConflict)
        let doc = try LFDocument(path: path)

        try doc.resolve(0, as: testCase.choice)
        try doc.save()

        #expect(box.readText(path) == testCase.expected)
    }

    @Test("the base choice keeps the common ancestor")
    func baseChoice() throws {
        let box = Sandbox()
        let path = box.write("a.txt", diff3Conflict)
        let doc = try LFDocument(path: path)

        try doc.resolve(0, as: .base)
        try doc.save()

        #expect(box.readText(path) == text("before", "base", "after"))
    }

    @Test("the base choice is rejected when the conflict has no base")
    func baseWithoutBase() throws {
        let box = Sandbox()
        let doc = try LFDocument(path: box.write("a.txt", simpleConflict))

        #expect(throws: LFError.self) { try doc.resolve(0, as: .base) }
    }

    @Test("a conflict index outside the range is rejected")
    func indexOutOfRange() throws {
        let box = Sandbox()
        let doc = try LFDocument(path: box.write("a.txt", simpleConflict))

        #expect(throws: LFError.self) { try doc.resolve(1, as: .current) }
        #expect(throws: LFError.self) { try doc.conflict(at: -1) }
    }

    @Test("custom text replaces the conflict")
    func customEdit() throws {
        let box = Sandbox()
        let path = box.write("a.txt", simpleConflict)
        let doc = try LFDocument(path: path)

        try doc.setCustom(0, bytes: Array(text("merged by hand").utf8))
        try doc.save()

        #expect(box.readText(path) == text("before", "merged by hand", "after"))
        #expect(try doc.conflict(at: 0).choice == .custom)
    }

    @Test("saving with unresolved conflicts fails and leaves the file untouched")
    func unresolvedRefusesToSave() throws {
        let box = Sandbox()
        let path = box.write("a.txt", simpleConflict)
        let doc = try LFDocument(path: path)

        #expect(throws: LFError.self) { try doc.save() }
        #expect(box.readText(path) == simpleConflict)
        #expect(doc.info.unresolvedCount == 1)
    }

    @Test("forced save keeps unresolved conflicts verbatim")
    func forcedSave() throws {
        let box = Sandbox()
        let path = box.write("a.txt", simpleConflict)
        let doc = try LFDocument(path: path)

        try doc.save(force: true)

        #expect(box.readText(path) == simpleConflict)
    }

    @Test("saving to another path leaves the source untouched")
    func saveElsewhere() throws {
        let box = Sandbox()
        let path = box.write("a.txt", simpleConflict)
        let doc = try LFDocument(path: path)
        try doc.resolveAll(as: .incoming)

        try doc.save(to: box.path("out.txt"))

        #expect(box.readText(path) == simpleConflict)
        #expect(box.readText(box.path("out.txt")) == text("before", "theirs1", "after"))
    }

    @Test("resolveAll applies one choice to every conflict")
    func resolveAll() throws {
        let box = Sandbox()
        let source = text("<<<<<<< a", "1a", "=======", "1b", ">>>>>>> b", "mid", "<<<<<<< a", "2a", "=======", "2b", ">>>>>>> b")
        let path = box.write("a.txt", source)
        let doc = try LFDocument(path: path)

        try doc.resolveAll(as: .current)
        try doc.save()

        #expect(doc.info.unresolvedCount == 0)
        #expect(box.readText(path) == text("1a", "mid", "2a"))
    }

    @Test("each conflict can take a different choice")
    func mixedChoices() throws {
        let box = Sandbox()
        let source = text("<<<<<<< a", "1a", "=======", "1b", ">>>>>>> b", "mid", "<<<<<<< a", "2a", "=======", "2b", ">>>>>>> b")
        let path = box.write("a.txt", source)
        let doc = try LFDocument(path: path)

        try doc.resolve(0, as: .incoming)
        try doc.resolve(1, as: .bothCurrentFirst)
        try doc.save()

        #expect(box.readText(path) == text("1b", "mid", "2a", "2b"))
    }

    @Test("CRLF line endings survive resolution")
    func crlfPreserved() throws {
        let box = Sandbox()
        let source = text("a", "<<<<<<< H", "x", "=======", "y", ">>>>>>> b", "z", eol: "\r\n")
        let path = box.write("a.txt", source)
        let doc = try LFDocument(path: path)

        try doc.resolve(0, as: .bothCurrentFirst)
        try doc.save()

        #expect(box.readText(path) == text("a", "x", "y", "z", eol: "\r\n"))
    }

    @Test("a missing final newline is preserved")
    func missingFinalNewline() throws {
        let box = Sandbox()
        let source = text("<<<<<<< a", "x", "=======", "y", ">>>>>>> b", "tail") + "end"
        let path = box.write("a.txt", source)
        let doc = try LFDocument(path: path)

        try doc.resolve(0, as: .current)
        try doc.save()

        #expect(box.readText(path) == text("x", "tail") + "end")
    }

    @Test("a UTF-8 byte order mark is preserved")
    func utf8BomPreserved() throws {
        let box = Sandbox()
        let source = [0xEF, 0xBB, 0xBF] + Array(simpleConflict.utf8)
        let path = box.write("a.txt", bytes: source)
        let doc = try LFDocument(path: path)

        try doc.resolve(0, as: .current)
        try doc.save()

        #expect(doc.info.encoding == .utf8Bom)
        #expect(box.read(path) == [0xEF, 0xBB, 0xBF] + Array(text("before", "ours1", "ours2", "after").utf8))
    }

    @Test("a conflict on the first line of a BOM file keeps the BOM")
    func utf8BomBeforeMarker() throws {
        let box = Sandbox()
        let source = [0xEF, 0xBB, 0xBF] + Array(text("<<<<<<< a", "x", "=======", "y", ">>>>>>> b").utf8)
        let path = box.write("a.txt", bytes: source)
        let doc = try LFDocument(path: path)

        try doc.resolve(0, as: .incoming)
        try doc.save()

        #expect(box.read(path) == [0xEF, 0xBB, 0xBF] + Array(text("y").utf8))
    }

    @Test("UTF-16 files are decoded, resolved and re-encoded", arguments: [false, true])
    func utf16RoundTrip(bigEndian: Bool) throws {
        let box = Sandbox()
        let source = text("\"key\" = \"héllo 😀\";", "<<<<<<< HEAD", "\"a\" = \"1\";", "=======", "\"a\" = \"2\";", ">>>>>>> b", "end")
        let path = box.write("Localizable.strings", bytes: utf16Bytes(source, bigEndian: bigEndian))
        let doc = try LFDocument(path: path)

        try doc.resolve(0, as: .incoming)
        try doc.save()

        let expected = text("\"key\" = \"héllo 😀\";", "\"a\" = \"2\";", "end")
        #expect(doc.info.encoding == (bigEndian ? .utf16BigEndian : .utf16LittleEndian))
        #expect(box.read(path) == utf16Bytes(expected, bigEndian: bigEndian))
    }

    @Test("saving keeps the file permissions")
    func permissionsKept() throws {
        let box = Sandbox()
        let path = box.write("run.sh", simpleConflict)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        let doc = try LFDocument(path: path)

        try doc.resolveAll(as: .current)
        try doc.save()

        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
    }

    @Test("saving leaves no temporary files behind")
    func noTemporaryFiles() throws {
        let box = Sandbox()
        let path = box.write("a.txt", simpleConflict)
        let doc = try LFDocument(path: path)
        try doc.resolveAll(as: .current)

        try doc.save()

        let names = try FileManager.default.contentsOfDirectory(atPath: box.root.path)
        #expect(names == ["a.txt"])
    }
}

@Suite("Probing")
struct ProbeTests {
    @Test("text, UTF-16 and binary files are told apart")
    func probeKinds() throws {
        let box = Sandbox()

        let plain = try LFFileProbe(path: box.write("a.txt", "hello\n"))
        let utf16 = try LFFileProbe(path: box.write("b.strings", bytes: utf16Bytes("hi\n")))
        let binary = try LFFileProbe(path: box.write("c.png", bytes: [0x89, 0x50, 0x00, 0x01]))

        #expect(plain.kind == .text)
        #expect(utf16.kind == .text)
        #expect(utf16.encoding == .utf16LittleEndian)
        #expect(binary.kind == .binary)
    }
}
