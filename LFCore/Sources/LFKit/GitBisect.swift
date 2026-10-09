import Foundation

public enum BisectMark: String, Sendable {
    case good, bad, skip
}

public enum BisectStep: Sendable, Equatable {
    /// HEAD is a commit to test; `remaining` is git's estimate of the revisions left.
    case testing(hash: String, remaining: Int?)
    /// The first bad commit.
    case found(String)
}

public enum IgnoreScope: Sendable, Equatable {
    /// `.gitignore` at the top of the repository, shared with everyone.
    case gitignore
    /// `.git/info/exclude`, only for this clone.
    case localExclude
}

extension GitClient {
    // MARK: Bisect

    public func isBisecting() throws -> Bool {
        let path = try git.run(["rev-parse", "--git-path", "BISECT_LOG"]).text
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : git.directory.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// The commit being tested right now (HEAD) while a bisect runs, otherwise nil.
    public func bisectCandidate() throws -> String? {
        try isBisecting() ? try git.run(["rev-parse", "HEAD"]).text : nil
    }

    /// Starts a binary search between a bad commit and an older good one.
    public func bisectStart(bad: String, good: String) throws -> BisectStep {
        try requireName(bad, what: "revision")
        try requireName(good, what: "revision")
        return try step(after: try git.run(["bisect", "start", bad, good, "--"]))
    }

    public func bisectMark(_ mark: BisectMark) throws -> BisectStep {
        try step(after: try git.run(["bisect", mark.rawValue]))
    }

    /// Ends the search and goes back to where it started.
    public func bisectReset() throws {
        try git.run(["bisect", "reset"])
    }

    private func step(after result: GitResult) throws -> BisectStep {
        let output = String(decoding: result.stdout, as: UTF8.self)
        for line in output.split(separator: "\n") where line.hasSuffix(" is the first bad commit") {
            return .found(String(line.prefix { !$0.isWhitespace }))
        }
        var remaining: Int?
        if let line = output.split(separator: "\n").first(where: { $0.hasPrefix("Bisecting: ") }) {
            remaining = line.split(separator: " ").compactMap { Int($0) }.first
        }
        return .testing(hash: try git.run(["rev-parse", "HEAD"]).text, remaining: remaining)
    }

    // MARK: Ignore

    /// Adds files to an ignore list. Names are written literally (a file called `[ab].txt` ignores only itself),
    /// and a file git already tracks is removed from the index, keeping it on disk.
    public func ignore(_ paths: [String], scope: IgnoreScope) throws {
        guard !paths.isEmpty else { return }
        let target: URL
        switch scope {
        case .gitignore:
            target = try git.repositoryRoot().appendingPathComponent(".gitignore")
        case .localExclude:
            let path = try git.run(["rev-parse", "--git-path", "info/exclude"]).text
            target = path.hasPrefix("/") ? URL(fileURLWithPath: path) : git.directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var content = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        let existing = Set(content.split(separator: "\n").map(String.init))
        for path in paths {
            let pattern = "/" + Self.escapedIgnorePattern(path)
            guard !existing.contains(pattern) else { continue }
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
            content += pattern + "\n"
        }
        try content.write(to: target, atomically: true, encoding: .utf8)

        let tracked = try paths.filter {
            try git.run(["ls-files", "--error-unmatch", "--", $0], allowedStatuses: [0, 1]).status == 0
        }
        if !tracked.isEmpty { try git.run(["rm", "--cached", "-r", "-q", "--"] + tracked) }
    }

    static func escapedIgnorePattern(_ path: String) -> String {
        var result = ""
        for character in path {
            if "\\*?[]".contains(character) { result.append("\\") }
            result.append(character)
        }
        if result.hasPrefix("#") || result.hasPrefix("!") { result = "\\" + result }
        if result.hasSuffix(" ") { result = String(result.dropLast()) + "\\ " }
        return result
    }
}
