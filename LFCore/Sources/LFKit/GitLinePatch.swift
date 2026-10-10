import Foundation

/// Where a patch from a commit is applied.
public enum PatchTarget: Sendable, Equatable {
    case index
    case workingTree
    case both
}

/// Staging, unstaging and discarding single lines, and reusing lines of old commits.
extension GitClient {
    // MARK: - Building a patch from selected lines

    /// A patch with only the selected lines of one hunk. `lines` are 1-based line numbers of the diff.
    ///
    /// Forward (`reverse: false`, for stage / apply): an unselected added line is left out, an unselected removed
    /// line stays as context. Reverse (for unstage / discard / revert): an unselected added line stays as
    /// context, an unselected removed line is left out.
    func partialPatch(of hunk: DiffHunk, in diff: GitDiffFile, selecting lines: Set<Int>, reverse: Bool) throws -> Data {
        let bytes = try diff.hunkBytes(hunk)
        var rawLines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false).map { Data($0) }
        if rawLines.last?.isEmpty == true { rawLines.removeLast() }
        guard rawLines.count > 1 else { throw GitClientError.unsupported("The hunk is empty.") }

        var body: [Data] = []
        var oldCount = 0, newCount = 0, changes = 0
        var previousKept = false
        for (offset, line) in rawLines.dropFirst().enumerated() {
            let number = hunk.headerLine + 1 + offset
            let selected = lines.contains(number)
            switch line.first {
            case 0x20: // context
                body.append(line); oldCount += 1; newCount += 1; previousKept = true
            case 0x2B: // added
                if selected {
                    body.append(line); newCount += 1; changes += 1; previousKept = true
                } else if reverse {
                    body.append(Data([0x20]) + line.dropFirst()); oldCount += 1; newCount += 1; previousKept = true
                } else {
                    previousKept = false
                }
            case 0x2D: // removed
                if selected {
                    body.append(line); oldCount += 1; changes += 1; previousKept = true
                } else if !reverse {
                    body.append(Data([0x20]) + line.dropFirst()); oldCount += 1; newCount += 1; previousKept = true
                } else {
                    previousKept = false
                }
            case 0x5C: // "\ No newline at end of file" belongs to the line before it
                if previousKept { body.append(line) }
            default:
                body.append(line); previousKept = true
            }
        }
        guard changes > 0 else { throw GitClientError.unsupported("Select at least one added or removed line.") }

        let start = reverse ? hunk.newStart : hunk.oldStart
        var patch = try plainHeader(of: diff)
        patch.append(Data("@@ -\(start),\(oldCount) +\(start),\(newCount) @@\n".utf8))
        for line in body { patch.append(line); patch.append(0x0A) }
        return patch
    }

    /// The path when the diff creates a file (`--- /dev/null`), otherwise nil.
    private func createdFilePath(of diff: GitDiffFile) throws -> String? {
        let text = String(decoding: try diff.fileHeader(), as: UTF8.self)
        guard text.contains("--- /dev/null"), let path = Self.headerPath(text) else { return nil }
        return path
    }

    private static func headerPath(_ header: String) -> String? {
        guard let first = header.split(separator: "\n").first, first.hasPrefix("diff --git a/"),
              let split = first.range(of: " b/", options: .backwards) else { return nil }
        return String(first[first.index(first.startIndex, offsetBy: "diff --git a/".count)..<split.lowerBound])
    }

    /// The file header; for an added or deleted file a plain modification header, because a partial patch no longer
    /// creates or removes the file.
    private func plainHeader(of diff: GitDiffFile) throws -> Data {
        let header = try diff.fileHeader()
        let text = String(decoding: header, as: UTF8.self)
        guard text.contains("--- /dev/null") || text.contains("+++ /dev/null"), let path = Self.headerPath(text) else { return header }
        return Data("diff --git a/\(path) b/\(path)\n--- a/\(path)\n+++ b/\(path)\n".utf8)
    }

    // MARK: - Index and work tree

    /// Stages (`stage: true`, for an unstaged diff) or unstages (`stage: false`, for a staged diff) only these lines.
    public func applyLines(_ lines: Set<Int>, in hunk: DiffHunk, of diff: GitDiffFile, stage: Bool) throws {
        let patch = try partialPatch(of: hunk, in: diff, selecting: lines, reverse: !stage)
        // A file git does not know yet has no index entry to patch: register it as "intent to add" (an empty
        // entry), so only the chosen lines go in and the rest stays unstaged.
        let newFile = stage ? try createdFilePath(of: diff) : nil
        if let newFile { try git.run(["add", "--intent-to-add", "--", newFile]) }
        do {
            try git.run(["apply", "--cached", "--recount", "--whitespace=nowarn"] + (stage ? [] : ["--reverse"]), stdin: patch)
        } catch {
            // Leave the file untracked again rather than half registered.
            if let newFile { _ = try? git.run(["rm", "--cached", "-q", "--", newFile]) }
            throw error
        }
    }

    /// Throws away only these lines of an unstaged diff.
    public func discardLines(_ lines: Set<Int>, in hunk: DiffHunk, of diff: GitDiffFile) throws {
        let patch = try partialPatch(of: hunk, in: diff, selecting: lines, reverse: true)
        try git.run(["apply", "--reverse", "--recount", "--whitespace=nowarn"], stdin: patch)
    }

    // MARK: - Lines of a commit

    /// Applies (or, with `reverse`, takes back) selected lines of a commit's diff.
    public func applyCommitLines(_ lines: Set<Int>, in hunk: DiffHunk, of diff: GitDiffFile, to target: PatchTarget,
                                 reverse: Bool) throws {
        let patch = try partialPatch(of: hunk, in: diff, selecting: lines, reverse: reverse)
        let place: [String] = switch target {
        case .index: ["--cached"]
        case .workingTree: []
        case .both: ["--index"]
        }
        try git.run(["apply", "--recount", "--whitespace=nowarn"] + place + (reverse ? ["--reverse"] : []), stdin: patch)
    }

    /// Takes the selected lines out of `commit`, rewriting the history after it. The work tree must be clean.
    public func removeLines(_ lines: Set<Int>, in hunk: DiffHunk, of diff: GitDiffFile, from commit: GitCommit) throws {
        guard try status().isClean else {
            throw GitClientError.unsupported("Commit or stash your changes first; the history is about to be rewritten.")
        }
        let patch = try partialPatch(of: hunk, in: diff, selecting: lines, reverse: true)
        let isHead = try git.run(["rev-parse", "HEAD"]).text == commit.hash
        if !isHead { try editCommit(commit) }
        do {
            try git.run(["apply", "--index", "--reverse", "--recount", "--whitespace=nowarn"], stdin: patch)
            try amendKeepingMessage(noVerify: true)
        } catch {
            if !isHead { try? abort(.rebase) } else { try? discardEverything() }
            throw error
        }
        if !isHead { try continueOperation(.rebase) }
    }
}
