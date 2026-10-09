import Foundation

/// One `@@ … @@` block of a unified diff.
public struct DiffHunk: Sendable, Equatable, Identifiable {
    /// 1-based line of the `@@` header in the diff text.
    public let headerLine: Int
    /// Lines of the hunk including its header.
    public let lineCount: Int
    public let byteStart: Int
    public let byteEnd: Int
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    /// The whole header line, e.g. `@@ -1,3 +1,4 @@ func title`.
    public let title: String

    public var id: Int { headerLine }
    public var lastLine: Int { headerLine + lineCount - 1 }
}

/// Where the hunks of one file's diff are, found in a single pass over its bytes.
public struct DiffIndex: Sendable, Equatable {
    public let lineCount: Int
    /// Lines before the first hunk (`diff --git`, `index`, `---`, `+++`, mode lines…).
    public let fileHeaderLineCount: Int
    public let fileHeaderByteCount: Int
    public let hunks: [DiffHunk]
    public let isBinary: Bool
}

public enum DiffParser {
    private static let hunkMarker = Array("@@ -".utf8)
    private static let binaryMarkers = [Array("Binary files ".utf8), Array("GIT binary patch".utf8)]

    public static func parse(_ buffer: UnsafeRawBufferPointer) -> DiffIndex {
        guard let base = buffer.baseAddress, !buffer.isEmpty else {
            return DiffIndex(lineCount: 0, fileHeaderLineCount: 0, fileHeaderByteCount: 0, hunks: [], isBinary: false)
        }
        let count = buffer.count
        var hunks: [DiffHunk] = []
        var open: (line: Int, byte: Int, fields: (Int, Int, Int, Int), title: String)?
        var isBinary = false
        var lineNumber = 0
        var offset = 0

        func close(atByte byte: Int, line: Int) {
            guard let open else { return }
            hunks.append(DiffHunk(
                headerLine: open.line, lineCount: line - open.line, byteStart: open.byte, byteEnd: byte,
                oldStart: open.fields.0, oldCount: open.fields.1, newStart: open.fields.2, newCount: open.fields.3,
                title: open.title
            ))
        }

        while offset < count {
            let newline = memchr(base + offset, 0x0A, count - offset)
            let lineEnd = newline.map { base.distance(to: UnsafeRawPointer($0)) } ?? count
            let next = newline == nil ? count : lineEnd + 1
            lineNumber += 1
            let line = UnsafeRawBufferPointer(start: base + offset, count: lineEnd - offset)
            if line.starts(with: hunkMarker) {
                close(atByte: offset, line: lineNumber)
                let text = String(decoding: line, as: UTF8.self)
                open = (lineNumber, offset, headerNumbers(text), text)
            } else if open == nil, binaryMarkers.contains(where: { line.starts(with: $0) }) {
                isBinary = true
            }
            offset = next
        }
        close(atByte: count, line: lineNumber + 1)
        let firstHunk = hunks.first
        return DiffIndex(
            lineCount: lineNumber,
            fileHeaderLineCount: firstHunk.map { $0.headerLine - 1 } ?? lineNumber,
            fileHeaderByteCount: firstHunk?.byteStart ?? count,
            hunks: hunks,
            isBinary: isBinary
        )
    }

    /// "@@ -a,b +c,d @@": a missing count means 1.
    private static func headerNumbers(_ header: String) -> (Int, Int, Int, Int) {
        func range(after marker: Character, in text: Substring) -> (Substring, Int, Int) {
            guard let start = text.firstIndex(of: marker) else { return (text, 0, 1) }
            let rest = text[text.index(after: start)...]
            let token = rest.prefix { $0.isNumber || $0 == "," }
            let numbers = token.split(separator: ",").compactMap { Int($0) }
            return (rest.dropFirst(token.count), numbers.first ?? 0, numbers.count > 1 ? numbers[1] : 1)
        }
        let (afterOld, oldStart, oldCount) = range(after: "-", in: header[...])
        let (_, newStart, newCount) = range(after: "+", in: afterOld)
        return (oldStart, oldCount, newStart, newCount)
    }
}

extension UnsafeRawBufferPointer {
    fileprivate func starts(with prefix: [UInt8]) -> Bool {
        count >= prefix.count && prefix.indices.allSatisfy { self[$0] == prefix[$0] }
    }
}

/// A unified diff of one file, kept on disk and read through the C engine, so a diff of millions of
/// lines costs no more memory than a small one. The temporary file is removed with the object.
public final class GitDiffFile: @unchecked Sendable {
    /// Bytes shown for one line at most; the rest is cut before decoding.
    public static let maxLineBytes = 16_000

    public let fileURL: URL
    public let index: DiffIndex
    /// nil when the engine cannot read the text (for example UTF-16 content).
    private let document: LFDocument?

    init(fileURL: URL, index: DiffIndex) {
        self.fileURL = fileURL
        self.index = index
        document = try? LFDocument(path: fileURL.path)
    }

    deinit {
        try? FileManager.default.removeItem(at: fileURL)
    }

    public var isDisplayable: Bool { document != nil }
    public var lineCount: Int { document?.info.lineCount ?? 0 }

    /// A 1-based line without its terminator.
    public func text(ofLine line: Int) -> String {
        guard let document, line >= 1, line <= lineCount, let start = try? document.lineOffset(line),
              let end = try? document.lineOffset(line + 1) else { return "" }
        let cut = end - start > Self.maxLineBytes
        var bytes = document.bytes(in: LFRange(offset: start, length: min(end - start, Self.maxLineBytes)))
        if cut {
            while let last = bytes.last, last & 0xC0 == 0x80 { bytes.removeLast() }
            if let last = bytes.last, last >= 0xC0 { bytes.removeLast() }
        }
        while let last = bytes.last, last == 0x0A || last == 0x0D { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self) + (cut ? "…" : "")
    }

    /// The file header plus one hunk: a patch `git apply` accepts on its own.
    public func patch(for hunk: DiffHunk) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var patch = try handle.read(upToCount: index.fileHeaderByteCount) ?? Data()
        try handle.seek(toOffset: UInt64(hunk.byteStart))
        patch.append(try handle.read(upToCount: hunk.byteEnd - hunk.byteStart) ?? Data())
        if patch.last != 0x0A { patch.append(0x0A) }
        return patch
    }
}

public enum DiffTarget: Sendable {
    /// Unstaged changes (`staged: false`) or staged changes of a tracked file.
    case workingTree(path: String, staged: Bool)
    case untracked(path: String)
    /// One file of a commit, compared with the commit's first parent.
    case commit(GitCommit, path: String, originalPath: String? = nil)
}

extension GitClient {
    /// The diff of one file, written to a temporary file and indexed.
    public func diff(of target: DiffTarget) throws -> GitDiffFile {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-diff-\(UUID().uuidString).diff")
        // Fixed prefixes: `git apply` expects a/ and b/ whatever diff.noprefix says.
        let common = ["diff", "--no-color", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/"]
        var allowed: Set<Int32> = [0]
        var arguments: [String]
        switch target {
        case .workingTree(let path, let staged):
            arguments = common + (staged ? ["--cached"] : []) + ["--", path]
        case .untracked(let path):
            arguments = common + ["--no-index", "--", "/dev/null", path]
            allowed = [0, 1] // --no-index exits 1 when the files differ
        case .commit(let commit, let path, let originalPath):
            arguments = common + ["-M", try baseRevision(of: commit), commit.hash, "--", path] + (originalPath.map { [$0] } ?? [])
        }
        do {
            try git.run(arguments, outputFile: url, allowedStatuses: allowed)
            let index = try Data(contentsOf: url, options: .alwaysMapped).withUnsafeBytes { DiffParser.parse($0) }
            return GitDiffFile(fileURL: url, index: index)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Stages (`stage: true`, for an unstaged diff) or unstages (`stage: false`, for a staged diff) one hunk.
    public func applyHunk(_ hunk: DiffHunk, of diff: GitDiffFile, stage: Bool) throws {
        let patch = try diff.patch(for: hunk)
        try git.run(["apply", "--cached", "--whitespace=nowarn"] + (stage ? [] : ["--reverse"]), stdin: patch)
    }
}
