import Foundation

/// Problems the client can tell apart before git has to complain.
public enum GitClientError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case emptyMessage
    case nothingToCommit
    case noRemote
    case notOnBranch
    case nothingToStash
    case unsupported(String)

    public var description: String {
        switch self {
        case .emptyMessage: "The commit message is empty."
        case .nothingToCommit: "There are no staged changes to commit."
        case .noRemote: "This repository has no remote."
        case .notOnBranch: "HEAD is detached; switch to a branch first."
        case .nothingToStash: "There are no local changes to stash."
        case .unsupported(let what): what
        }
    }

    public var errorDescription: String? { description }
}

/// A merge-like operation that stops in the middle when there are conflicts.
public enum GitOperation: Sendable, Equatable, CaseIterable {
    case merge
    case rebase
    case cherryPick
    case revert

    public var title: String {
        switch self {
        case .merge: "Merge"
        case .rebase: "Rebase"
        case .cherryPick: "Cherry-pick"
        case .revert: "Revert"
        }
    }

    fileprivate var command: String {
        switch self {
        case .merge: "merge"
        case .rebase: "rebase"
        case .cherryPick: "cherry-pick"
        case .revert: "revert"
        }
    }
}

public struct GitBranch: Sendable, Equatable, Identifiable {
    /// Short name: `main`, or `origin/main` for a remote-tracking branch.
    public let name: String
    public let isCurrent: Bool
    public let isRemote: Bool
    public let upstream: String?
    public let tip: String
    /// Commits only here (to push) and only on the upstream (to pull), as of the last fetch. Zero without an upstream.
    public var ahead = 0
    public var behind = 0

    public var id: String { (isRemote ? "remote:" : "local:") + name }
}

public enum PullStrategy: Sendable, Equatable, CaseIterable {
    case fastForwardOnly
    case merge
    case rebase

    var arguments: [String] {
        switch self {
        case .fastForwardOnly: ["--ff-only"]
        case .merge: ["--no-rebase", "--no-ff"]
        case .rebase: ["--rebase"]
        }
    }
}

/// Git operations of a client: everything runs through the user's own `git`, so credentials, hooks,
/// signing and configuration behave exactly as they do in a terminal.
public struct GitClient: Sendable {
    public let git: Git

    /// Never let git open an editor: the app supplies messages itself.
    static let noEditor = ["-c", "core.editor=true"]
    /// $GIT_EDITOR and $GIT_SEQUENCE_EDITOR would win over `core.editor`.
    static let noEditorEnvironment = ["GIT_EDITOR": "true", "GIT_SEQUENCE_EDITOR": "true"]

    /// How long a fetch, pull or push may run before it is stopped.
    public static let defaultRemoteTimeout: TimeInterval = 300

    public init(directory: URL, log: GitCommandLog? = nil) {
        git = Git(directory: directory, log: log)
    }

    // MARK: - Status

    public func status() throws -> GitStatus {
        let result = try git.run(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"])
        return try GitStatusParser.parse(result.stdout)
    }

    // MARK: - Staging

    public func stage(_ paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try git.run(["add", "--"] + paths)
    }

    public func unstage(_ paths: [String]) throws {
        guard !paths.isEmpty else { return }
        if try hasCommits() {
            try git.run(["restore", "--staged", "--"] + paths)
        } else {
            // -f: a file edited after it was added differs from both the index and HEAD, which plain rm refuses.
            try git.run(["rm", "--cached", "-r", "-q", "-f", "--"] + paths)
        }
    }

    /// Throws away unstaged edits: tracked files go back to the index, untracked files are deleted.
    public func discard(_ changes: [GitChange]) throws {
        let tracked = changes.filter { $0.kind != .untracked && $0.isUnstaged }.map(\.path)
        let untracked = changes.filter { $0.kind == .untracked }.map(\.path)
        if !tracked.isEmpty {
            try git.run(["restore", "--"] + tracked)
        }
        if !untracked.isEmpty {
            try git.run(["clean", "-f", "-d", "-q", "--"] + untracked)
        }
    }

    private func hasCommits() throws -> Bool {
        try git.run(["rev-parse", "--verify", "-q", "HEAD"], allowedStatuses: [0, 1]).status == 0
    }

    // MARK: - Commit

    /// Commits the staged changes (or amends the last commit) and returns the new short hash.
    @discardableResult
    public func commit(message: String, amend: Bool = false, noVerify: Bool = false) throws -> String {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitClientError.emptyMessage
        }
        if !amend, try git.run(["diff", "--cached", "--quiet"], allowedStatuses: [0, 1]).status == 0 {
            throw GitClientError.nothingToCommit
        }
        var arguments = ["commit", "-q", "--cleanup=whitespace", "-F", "-"]
        if amend { arguments.append("--amend") }
        if noVerify { arguments.append("--no-verify") }
        try git.run(arguments, stdin: Data(message.utf8))
        return try git.run(["rev-parse", "--short", "HEAD"]).text
    }

    /// Adds the staged changes to the last commit and keeps its message.
    public func amendKeepingMessage(noVerify: Bool = false) throws {
        try git.run(Self.noEditor + ["commit", "-q", "--amend", "--no-edit"] + (noVerify ? ["--no-verify"] : []),
                    environment: Self.noEditorEnvironment)
    }

    /// The full message of HEAD, for amending; nil before the first commit.
    public func lastCommitMessage() throws -> String? {
        let result = try git.run(["log", "-1", "--format=%B"], allowedStatuses: [0, 128])
        guard result.status == 0 else { return nil }
        return result.text
    }

    // MARK: - Branches

    public func branches() throws -> [GitBranch] {
        let format = "%(refname)%1f%(HEAD)%1f%(upstream:short)%1f%(objectname:short)%1f%(upstream:track,nobracket)"
        let result = try git.run(["for-each-ref", "--format=\(format)", "refs/heads", "refs/remotes"])
        var branches: [GitBranch] = []
        for line in String(decoding: result.stdout, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5 else { continue }
            let isRemote = fields[0].hasPrefix("refs/remotes/")
            let name = String(fields[0].dropFirst(isRemote ? "refs/remotes/".count : "refs/heads/".count))
            if isRemote && name.hasSuffix("/HEAD") { continue }
            let track = Self.parseTrack(fields[4])
            branches.append(GitBranch(name: name, isCurrent: fields[1] == "*", isRemote: isRemote,
                                      upstream: fields[2].isEmpty ? nil : fields[2], tip: fields[3],
                                      ahead: track.ahead, behind: track.behind))
        }
        return branches
    }

    /// Reads git's `ahead 2, behind 1` (also `ahead 2`, `behind 1`, `gone`, or empty when level).
    static func parseTrack(_ text: String) -> (ahead: Int, behind: Int) {
        var result = (ahead: 0, behind: 0)
        for part in text.split(separator: ",") {
            let words = part.split(separator: " ")
            guard words.count == 2, let count = Int(words[1]) else { continue }
            if words[0] == "ahead" { result.ahead = count } else if words[0] == "behind" { result.behind = count }
        }
        return result
    }

    /// Switches to a local branch, or creates a tracking branch from a remote one (`origin/feature`).
    /// Names and start points reach git as plain arguments: one that looks like an option would be run as one.
    func requireName(_ name: String, what: String = "branch name") throws {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.contains("\0") else {
            throw GitClientError.unsupported("'\(name)' is not a valid \(what).")
        }
    }

    public func switchBranch(_ name: String, discardChanges: Bool = false) throws {
        try requireName(name)
        if discardChanges {
            try git.run(["switch", "--discard-changes", name])
            return
        }
        let isLocal = try git.run(["show-ref", "--verify", "--quiet", "refs/heads/\(name)"], allowedStatuses: [0, 1]).status == 0
        let isRemote = try git.run(["show-ref", "--verify", "--quiet", "refs/remotes/\(name)"], allowedStatuses: [0, 1]).status == 0
        if !isLocal && isRemote {
            try git.run(["switch", "--track", name])
        } else {
            try git.run(["switch", name])
        }
    }

    public func createBranch(_ name: String, from startPoint: String? = nil) throws {
        try requireName(name)
        if let startPoint { try requireName(startPoint, what: "start point") }
        try git.run(["switch", "-c", name] + (startPoint.map { [$0] } ?? []))
    }

    public func deleteBranch(_ name: String, force: Bool = false) throws {
        try requireName(name)
        try git.run(["branch", force ? "-D" : "-d", "--", name])
    }

    // MARK: - Operations in progress

    /// The merge, rebase, cherry-pick or revert that is waiting for the user, if any.
    public func operation() throws -> GitOperation? {
        let gitDirectory = URL(fileURLWithPath: try git.run(["rev-parse", "--absolute-git-dir"]).text, isDirectory: true)
        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: gitDirectory.appendingPathComponent(name).path)
        }
        // A rebase runs cherry-picks internally, so it has to be checked first.
        if exists("rebase-merge") || exists("rebase-apply") { return .rebase }
        if exists("MERGE_HEAD") { return .merge }
        if exists("CHERRY_PICK_HEAD") { return .cherryPick }
        if exists("REVERT_HEAD") { return .revert }
        return nil
    }

    public func continueOperation(_ operation: GitOperation) throws {
        try git.run(Self.noEditor + [operation.command, "--continue"], environment: Self.noEditorEnvironment)
    }

    public func abort(_ operation: GitOperation) throws {
        try git.run([operation.command, "--abort"])
    }

    /// Skips the current commit of a rebase or cherry-pick.
    public func skip(_ operation: GitOperation) throws {
        guard operation == .rebase || operation == .cherryPick else {
            throw GitClientError.unsupported("\(operation.title) cannot be skipped; abort it instead.")
        }
        try git.run(Self.noEditor + [operation.command, "--skip"], environment: Self.noEditorEnvironment)
    }

    // MARK: - Remotes

    func requireRemote() throws -> [String] {
        let remotes = try git.run(["remote"]).text.split(separator: "\n").map(String.init)
        guard !remotes.isEmpty else { throw GitClientError.noRemote }
        return remotes
    }

    public func fetch(timeout: TimeInterval? = defaultRemoteTimeout, cancellation: GitCancellation? = nil) throws {
        _ = try requireRemote()
        try git.run(["fetch", "--prune", "-q"], timeout: timeout, cancellation: cancellation)
    }

    public func pull(_ strategy: PullStrategy = .fastForwardOnly, timeout: TimeInterval? = defaultRemoteTimeout,
                     cancellation: GitCancellation? = nil) throws {
        _ = try requireRemote()
        try git.run(["pull", "-q"] + strategy.arguments, timeout: timeout, cancellation: cancellation)
    }

    /// Pushes the current branch; a branch without an upstream is published with `-u`.
    /// `force` uses `--force-with-lease`: it overwrites the remote branch only if nobody else pushed to it meanwhile.
    public func push(force: Bool = false, timeout: TimeInterval? = defaultRemoteTimeout,
                     cancellation: GitCancellation? = nil) throws {
        let remotes = try requireRemote()
        let status = try status()
        guard let branch = status.branch else { throw GitClientError.notOnBranch }
        let flags = force ? ["--force-with-lease"] : []
        if status.upstream != nil {
            try git.run(["push", "-q"] + flags, timeout: timeout, cancellation: cancellation)
        } else {
            try git.run(["push", "-q", "-u"] + flags + [remotes.contains("origin") ? "origin" : remotes[0], branch],
                        timeout: timeout, cancellation: cancellation)
        }
    }
}
