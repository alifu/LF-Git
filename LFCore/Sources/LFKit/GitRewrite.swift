import Foundation

/// Changing old commits, done like lazygit does it: an interactive rebase whose todo list the app writes itself,
/// so no editor ever opens.
extension GitClient {
    private struct RangeCommit {
        let hash: String
        let parents: [String]
    }

    // MARK: - Public actions

    /// Changes the message of any commit on the current branch.
    public func rewordCommit(_ commit: GitCommit, message: String) throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitClientError.emptyMessage }
        let messageFile = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-msg-\(UUID().uuidString)")
        try Data(message.utf8).write(to: messageFile)
        // Kept if the rebase stops (a failing hook, a conflict later on): `rebase --continue` runs the exec again.
        var finished = false
        defer { if finished { try? FileManager.default.removeItem(at: messageFile) } }
        let amend = "exec git commit --amend -q --no-verify --cleanup=whitespace -F \(Self.shellQuoted(messageFile.path))"
        try rewrite(from: commit.parents.first) { range in
            try Self.require(range.first?.hash == commit.hash, "That commit is not on the current branch.")
            return range.flatMap { ["pick \($0.hash)"] + ($0.hash == commit.hash ? [amend] : []) }
        }
        finished = true
    }

    public func dropCommit(_ commit: GitCommit) throws {
        try rewrite(from: commit.parents.first) { range in
            try Self.require(range.first?.hash == commit.hash, "That commit is not on the current branch.")
            return range.map { ($0.hash == commit.hash ? "drop " : "pick ") + $0.hash }
        }
    }

    /// Stops a rebase right after the commit so it can be changed; continue the operation when done.
    public func editCommit(_ commit: GitCommit) throws {
        try rewrite(from: commit.parents.first) { range in
            try Self.require(range.first?.hash == commit.hash, "That commit is not on the current branch.")
            return range.map { ($0.hash == commit.hash ? "edit " : "pick ") + $0.hash }
        }
    }

    /// Folds the commit into the one before it; both messages are kept.
    public func squashCommit(_ commit: GitCommit) throws {
        try fold(commit, action: "squash")
    }

    /// Folds the commit into the one before it; only the older message is kept.
    public func fixupCommit(_ commit: GitCommit) throws {
        try fold(commit, action: "fixup")
    }

    /// Swaps the commit with the next newer one.
    public func moveCommitUp(_ commit: GitCommit) throws {
        try rewrite(from: commit.parents.first) { range in
            try Self.require(range.first?.hash == commit.hash, "That commit is not on the current branch.")
            try Self.require(range.count > 1, "This is the newest commit; it cannot move up.")
            var order = range.map(\.hash)
            order.swapAt(0, 1)
            return order.map { "pick \($0)" }
        }
    }

    /// Swaps the commit with the one before it.
    public func moveCommitDown(_ commit: GitCommit) throws {
        guard let parent = commit.parents.first else {
            throw GitClientError.unsupported("This is the oldest commit; it cannot move down.")
        }
        let parentCommit = try rangeCommits(after: nil, upTo: parent, single: true).first
        try rewrite(from: parentCommit?.parents.first) { range in
            try Self.require(range.count > 1, "This is the oldest commit; it cannot move down.")
            try Self.require(range[0].hash == parent && range[1].hash == commit.hash, "That commit is not on the current branch.")
            var order = range.map(\.hash)
            order.swapAt(0, 1)
            return order.map { "pick \($0)" }
        }
    }

    /// Records the staged changes as a `fixup!` commit for `commit`; `autosquash` folds it in later.
    public func createFixupCommit(for commit: GitCommit) throws {
        try git.run(["commit", "-q", "--fixup=\(commit.hash)"])
    }

    /// Folds every `fixup!`/`squash!` commit above `commit` (and `commit` itself) into its target.
    public func autosquash(above commit: GitCommit) throws {
        let base = commit.parents.first
        try git.run(
            Self.noEditor + ["rebase", "-i", "--autostash", "--autosquash", "--keep-empty", "--empty=keep"] + (base.map { [$0] } ?? ["--root"]),
            environment: Self.noEditorEnvironment, literalPathspecs: false
        )
    }

    /// Puts the staged changes into an older commit.
    public func amendCommit(_ commit: GitCommit) throws {
        let head = try git.run(["rev-parse", "HEAD"]).text
        if head == commit.hash {
            try amendKeepingMessage()
            return
        }
        try createFixupCommit(for: commit)
        try autosquash(above: commit)
    }

    // MARK: - Engine

    private func fold(_ commit: GitCommit, action: String) throws {
        guard let parent = commit.parents.first else {
            throw GitClientError.unsupported("The oldest commit has nothing before it to fold into.")
        }
        let parentCommit = try rangeCommits(after: nil, upTo: parent, single: true).first
        try rewrite(from: parentCommit?.parents.first) { range in
            try Self.require(range.count > 1 && range[0].hash == parent && range[1].hash == commit.hash,
                             "That commit is not on the current branch.")
            return range.enumerated().map { ($0.offset == 1 ? "\(action) " : "pick ") + $0.element.hash }
        }
    }

    /// Runs an interactive rebase from `base` (nil = from the very first commit) with the todo list `plan` returns.
    private func rewrite(from base: String?, plan: ([RangeCommit]) throws -> [String]) throws {
        let range = try rangeCommits(after: base, upTo: "HEAD")
        guard !range.contains(where: { $0.parents.count > 1 }) else {
            throw GitClientError.unsupported("This part of the history contains a merge commit; it cannot be rewritten here.")
        }
        let todo = try plan(range).joined(separator: "\n") + "\n"
        let todoFile = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-todo-\(UUID().uuidString)")
        try Data(todo.utf8).write(to: todoFile)
        defer { try? FileManager.default.removeItem(at: todoFile) }

        var environment = Self.noEditorEnvironment
        environment["GIT_SEQUENCE_EDITOR"] = "cp \(Self.shellQuoted(todoFile.path))"
        try git.run(
            Self.noEditor + ["rebase", "-i", "--autostash", "--no-autosquash", "--keep-empty", "--empty=keep"]
                + (base.map { [$0] } ?? ["--root"]),
            environment: environment, literalPathspecs: false
        )
    }

    /// Commits from `base` (exclusive) to `tip`, oldest first.
    private func rangeCommits(after base: String?, upTo tip: String, single: Bool = false) throws -> [RangeCommit] {
        var arguments = ["rev-list", "--reverse", "--topo-order", "--parents"]
        if single { arguments.append("--max-count=1") }
        arguments.append(base.map { "\($0)..\(tip)" } ?? tip)
        let output = String(decoding: try git.run(arguments).stdout, as: UTF8.self)
        return output.split(separator: "\n").map { line in
            let hashes = line.split(separator: " ").map(String.init)
            return RangeCommit(hash: hashes[0], parents: Array(hashes.dropFirst()))
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw GitClientError.unsupported(message) }
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
