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
    /// Line number in the old / new file of every diff line (0 = none). Tracked up to `maxNumberedLines`.
    private let oldNumbers: [Int32]
    private let newNumbers: [Int32]

    static let maxNumberedLines = 4_000_000

    init(lineCount: Int, fileHeaderLineCount: Int, fileHeaderByteCount: Int, hunks: [DiffHunk], isBinary: Bool,
         oldNumbers: [Int32] = [], newNumbers: [Int32] = []) {
        self.lineCount = lineCount
        self.fileHeaderLineCount = fileHeaderLineCount
        self.fileHeaderByteCount = fileHeaderByteCount
        self.hunks = hunks
        self.isBinary = isBinary
        self.oldNumbers = oldNumbers
        self.newNumbers = newNumbers
    }

    /// The old- and new-file line numbers of a 1-based diff line; 0 when the line has none on that side.
    public func numbers(ofLine line: Int) -> (old: Int, new: Int) {
        guard line >= 1, line <= oldNumbers.count else { return (0, 0) }
        return (Int(oldNumbers[line - 1]), Int(newNumbers[line - 1]))
    }
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
        let tracksNumbers = count < DiffIndex.maxNumberedLines * 8 // a rough bound before the exact line count is known
        var oldNumbers: [Int32] = []
        var newNumbers: [Int32] = []
        var oldCounter = 0
        var newCounter = 0

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
            var old = 0, new = 0
            if line.starts(with: hunkMarker) {
                close(atByte: offset, line: lineNumber)
                let text = String(decoding: line, as: UTF8.self)
                let fields = headerNumbers(text)
                open = (lineNumber, offset, fields, text)
                (oldCounter, newCounter) = (fields.0, fields.2)
            } else if open == nil {
                if binaryMarkers.contains(where: { line.starts(with: $0) }) { isBinary = true }
            } else if let first = line.first {
                switch first {
                case 0x20: (old, new) = (oldCounter, newCounter); oldCounter += 1; newCounter += 1 // context
                case 0x2D: old = oldCounter; oldCounter += 1 // removed
                case 0x2B: new = newCounter; newCounter += 1 // added
                default: break // "\ No newline at end of file"
                }
            }
            if tracksNumbers && lineNumber <= DiffIndex.maxNumberedLines {
                oldNumbers.append(Int32(truncatingIfNeeded: old))
                newNumbers.append(Int32(truncatingIfNeeded: new))
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
            isBinary: isBinary,
            oldNumbers: oldNumbers,
            newNumbers: newNumbers
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

/// How a diff is produced. The defaults are git's own.
public struct DiffOptions: Sendable, Equatable {
    /// Hide changes that only touch whitespace. A diff made this way cannot be staged hunk by hunk.
    public var ignoreWhitespace = false
    /// Lines of context around a change; nil = git's default (3).
    public var contextLines: Int?
    public var detectRenames = true

    public init(ignoreWhitespace: Bool = false, contextLines: Int? = nil, detectRenames: Bool = true) {
        self.ignoreWhitespace = ignoreWhitespace
        self.contextLines = contextLines.map { min(max($0, 0), 1000) }
        self.detectRenames = detectRenames
    }

    var arguments: [String] {
        (ignoreWhitespace ? ["-w"] : []) + (contextLines.map { ["-U\($0)"] } ?? []) + (detectRenames ? [] : ["--no-renames"])
    }
}

/// A unified diff of one file, kept on disk and read through the C engine, so a diff of millions of
/// lines costs no more memory than a small one. The temporary file is removed with the object.
public final class GitDiffFile: @unchecked Sendable {
    /// Bytes shown for one line at most; the rest is cut before decoding.
    public static let maxLineBytes = 16_000

    public let fileURL: URL
    public let index: DiffIndex
    public let options: DiffOptions
    /// nil when the engine cannot read the text (for example UTF-16 content).
    private let document: LFDocument?

    init(fileURL: URL, index: DiffIndex, options: DiffOptions = DiffOptions()) {
        self.fileURL = fileURL
        self.index = index
        self.options = options
        document = try? LFDocument(path: fileURL.path)
    }

    deinit {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Removes diff files left behind by a crash or a force quit. Call once at launch.
    public static func sweepStaleTemporaryFiles(olderThan age: TimeInterval = 86_400) {
        let directory = FileManager.default.temporaryDirectory
        let cutoff = Date(timeIntervalSinceNow: -age)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix("lfgit-diff-") && name.hasSuffix(".diff") {
            let url = directory.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    public var isDisplayable: Bool { document != nil }

    /// Hunks and lines can be staged only from a diff that matches the file byte for byte.
    public var isStageable: Bool { !options.ignoreWhitespace && options.contextLines != 0 }

    /// Old- and new-file line numbers of a diff line (0 = none).
    public func numbers(ofLine line: Int) -> (old: Int, new: Int) {
        index.numbers(ofLine: line)
    }
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
        var patch = try fileHeader()
        patch.append(try hunkBytes(hunk))
        if patch.last != 0x0A { patch.append(0x0A) }
        return patch
    }

    /// `diff --git`, `index`, `---` and `+++` lines.
    func fileHeader() throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        return try handle.read(upToCount: index.fileHeaderByteCount) ?? Data()
    }

    /// The hunk's own bytes, `@@` line included.
    func hunkBytes(_ hunk: DiffHunk) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(hunk.byteStart))
        return try handle.read(upToCount: hunk.byteEnd - hunk.byteStart) ?? Data()
    }
}

public enum DiffTarget: Sendable {
    /// Unstaged changes (`staged: false`) or staged changes of a tracked file.
    case workingTree(path: String, staged: Bool)
    case untracked(path: String)
    /// One file of a commit, compared with the commit's first parent.
    case commit(GitCommit, path: String, originalPath: String? = nil)
    /// One file between two revisions (branches, tags, commits).
    case range(from: String, to: String, path: String, originalPath: String? = nil)
}

extension GitClient {
    /// The diff of one file, written to a temporary file and indexed.
    public func diff(of target: DiffTarget, options: DiffOptions = DiffOptions()) throws -> GitDiffFile {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-diff-\(UUID().uuidString).diff")
        // Fixed prefixes: `git apply` expects a/ and b/ whatever diff.noprefix says.
        // --no-textconv: a hunk is applied as a patch, so it has to be the file's real text.
        let common = ["diff", "--no-color", "--no-ext-diff", "--no-textconv", "--src-prefix=a/", "--dst-prefix=b/"] + options.arguments
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
        case .range(let from, let to, let path, let originalPath):
            try requireName(from, what: "revision")
            try requireName(to, what: "revision")
            arguments = common + ["-M", from, to, "--", path] + (originalPath.map { [$0] } ?? [])
        }
        do {
            try git.run(arguments, outputFile: url, allowedStatuses: allowed)
            let index = try Data(contentsOf: url, options: .alwaysMapped).withUnsafeBytes { DiffParser.parse($0) }
            return GitDiffFile(fileURL: url, index: index, options: options)
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
