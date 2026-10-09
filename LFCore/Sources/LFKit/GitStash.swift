import Foundation

public struct GitStash: Sendable, Equatable, Identifiable {
    /// Where the stash is now, e.g. `stash@{0}`. Moves when other stashes are added or dropped.
    public let ref: String
    public let message: String
    /// The branch the stash was made on, when git recorded it.
    public let branch: String?
    /// The stash commit; its diff against the first parent is the stashed change.
    public let commit: GitCommit

    public var id: String { commit.hash }
    public var hash: String { commit.hash }
    public var date: Date { commit.date }
}

extension GitClient {
    private static let stashFormat = ["%H", "%P", "%an", "%ae", "%at", "%gd", "%gs"].joined(separator: "%x1f")

    public func stashes() throws -> [GitStash] {
        let result = try git.run(["stash", "list", "-z", "--format=\(Self.stashFormat)"])
        return result.stdout.split(separator: 0, omittingEmptySubsequences: true).compactMap { record in
            let fields = String(decoding: record, as: UTF8.self).components(separatedBy: "\u{1F}")
            guard fields.count >= 7 else { return nil }
            let (branch, message) = Self.splitStashSubject(fields[6...].joined(separator: "\u{1F}"))
            let commit = GitCommit(
                hash: fields[0], parents: fields[1].split(separator: " ").map(String.init), authorName: fields[2],
                authorEmail: fields[3], date: Date(timeIntervalSince1970: TimeInterval(fields[4]) ?? 0), refs: [],
                subject: message
            )
            return GitStash(ref: fields[5], message: message, branch: branch, commit: commit)
        }
    }

    /// "On main: text" and "WIP on main: abc1234 subject" become (branch, text).
    private static func splitStashSubject(_ subject: String) -> (String?, String) {
        for prefix in ["WIP on ", "On "] where subject.hasPrefix(prefix) {
            let rest = subject.dropFirst(prefix.count)
            if let colon = rest.range(of: ": ") {
                return (String(rest[..<colon.lowerBound]), String(rest[colon.upperBound...]))
            }
        }
        return (nil, subject)
    }

    /// Saves local changes away. `paths` limits the stash to those files.
    public func stashPush(message: String? = nil, includeUntracked: Bool = false, stagedOnly: Bool = false,
                          keepIndex: Bool = false, paths: [String] = []) throws {
        var arguments = ["stash", "push"]
        if includeUntracked { arguments.append("--include-untracked") }
        if stagedOnly { arguments.append("--staged") }
        if keepIndex { arguments.append("--keep-index") }
        if let message, !message.isEmpty { arguments += ["-m", message] }
        if !paths.isEmpty { arguments += ["--"] + paths.map { ":(literal)\($0)" } }
        let result = try git.run(arguments, literalPathspecs: false)
        if result.text.contains("No local changes to save") { throw GitClientError.nothingToStash }
    }

    public func stashApply(_ stash: GitStash) throws {
        try git.run(["stash", "apply", "--index", try currentRef(of: stash)], literalPathspecs: false)
    }

    /// Applies and drops the stash. If applying conflicts, git keeps the stash and this throws.
    public func stashPop(_ stash: GitStash) throws {
        try git.run(["stash", "pop", "--index", try currentRef(of: stash)], literalPathspecs: false)
    }

    public func stashDrop(_ stash: GitStash) throws {
        try git.run(["stash", "drop", "-q", try currentRef(of: stash)])
    }

    public func stashRename(_ stash: GitStash, to message: String) throws {
        try git.run(["stash", "drop", "-q", try currentRef(of: stash)])
        do {
            try git.run(["stash", "store", "-m", message, stash.hash])
        } catch {
            // The commit still exists; put it back under its old name rather than lose it.
            _ = try? git.run(["stash", "store", "-m", stash.message, stash.hash])
            throw error
        }
    }

    /// Creates a branch from the commit the stash was made on, applies the stash, and drops it.
    public func stashBranch(_ name: String, from stash: GitStash) throws {
        try requireName(name)
        try git.run(["stash", "branch", name, try currentRef(of: stash)], literalPathspecs: false)
    }

    /// The stash's current position: other stashes may have been added since it was listed.
    private func currentRef(of stash: GitStash) throws -> String {
        guard let current = try stashes().first(where: { $0.hash == stash.hash }) else {
            throw GitClientError.unsupported("That stash no longer exists.")
        }
        return current.ref
    }
}
