import Foundation

public enum MergeMode: Sendable, Equatable, CaseIterable {
    /// Fast-forward when possible, otherwise a merge commit.
    case `default`
    case noFastForward
    case fastForwardOnly
    /// Stage the combined changes without committing.
    case squash

    public var title: String {
        switch self {
        case .default: "Merge"
        case .noFastForward: "Merge (always create a merge commit)"
        case .fastForwardOnly: "Fast-forward only"
        case .squash: "Squash and stage"
        }
    }

    var arguments: [String] {
        switch self {
        case .default: []
        case .noFastForward: ["--no-ff"]
        case .fastForwardOnly: ["--ff-only"]
        case .squash: ["--squash"]
        }
    }
}

public enum ResetMode: String, Sendable, CaseIterable {
    /// Move the branch only.
    case soft
    /// Move the branch and reset the index; the files stay as they are.
    case mixed
    /// Move the branch and make index and files match; edits are lost.
    case hard
}

extension GitClient {
    public func renameBranch(_ name: String, to newName: String) throws {
        try requireName(name)
        try requireName(newName)
        try git.run(["branch", "-m", name, newName])
    }

    /// Merges `name` into the current branch. A merge that conflicts throws and stays in progress.
    public func mergeBranch(_ name: String, mode: MergeMode = .default) throws {
        try requireName(name)
        try git.run(Self.noEditor + ["merge", "--no-edit"] + mode.arguments + [name], environment: Self.noEditorEnvironment)
    }

    /// Replays the current branch on top of `branch`. Local edits are stashed and brought back.
    public func rebase(onto branch: String) throws {
        try requireName(branch)
        try git.run(Self.noEditor + ["rebase", "--autostash", branch], environment: Self.noEditorEnvironment,
                    literalPathspecs: false)
    }

    public func reset(to revision: String, mode: ResetMode) throws {
        try requireName(revision, what: "revision")
        try git.run(["reset", "--\(mode.rawValue)", revision, "--"])
    }

    public func setUpstream(of branch: String, to upstream: String) throws {
        try requireName(branch)
        try requireName(upstream, what: "upstream")
        try git.run(["branch", "--set-upstream-to=\(upstream)", branch])
    }

    public func unsetUpstream(of branch: String) throws {
        try requireName(branch)
        try git.run(["branch", "--unset-upstream", branch])
    }

    public func deleteRemoteBranch(_ name: String, on remote: String, timeout: TimeInterval? = defaultRemoteTimeout,
                                   cancellation: GitCancellation? = nil) throws {
        try requireName(name)
        try requireName(remote, what: "remote name")
        try git.run(["push", "-q", remote, "--delete", name], timeout: timeout, cancellation: cancellation)
    }

    /// Moves a local branch forward to its upstream, which must already be fetched. Works for a branch that
    /// is not checked out; if it is the current branch the work tree is updated too.
    public func fastForward(_ branch: String) throws {
        try requireName(branch)
        guard let found = try branches().first(where: { $0.name == branch && !$0.isRemote }), let upstream = found.upstream else {
            throw GitClientError.unsupported("'\(branch)' has no upstream branch.")
        }
        if found.isCurrent {
            try git.run(["merge", "--ff-only", upstream])
        } else {
            // "origin/feature/x" -> fetch the remote's own branch into the local one; git refuses non-fast-forwards.
            guard let slash = upstream.firstIndex(of: "/") else { return }
            let remote = String(upstream[..<slash]), remoteBranch = String(upstream[upstream.index(after: slash)...])
            try git.run(["fetch", "-q", remote, "\(remoteBranch):\(branch)"])
        }
    }

    /// Back to the branch that was checked out before this one (`git switch -`).
    public func switchPrevious() throws {
        try git.run(["switch", "-"])
    }

    public func checkoutDetached(_ commit: GitCommit) throws {
        try git.run(["switch", "--detach", commit.hash])
    }

    /// Throws away every local edit and every untracked file (ignored files stay).
    public func discardEverything() throws {
        if try git.run(["rev-parse", "--verify", "-q", "HEAD"], allowedStatuses: [0, 1]).status == 0 {
            try git.run(["reset", "--hard", "-q"])
        }
        try git.run(["clean", "-f", "-d", "-q"])
    }

    // MARK: - Commits

    public func revert(_ commit: GitCommit) throws {
        try git.run(Self.noEditor + ["revert", "--no-edit"] + (commit.isMerge ? ["-m", "1"] : []) + [commit.hash],
                    environment: Self.noEditorEnvironment)
    }

    /// Copies commits onto the current branch; pass them oldest first.
    public func cherryPick(_ commits: [GitCommit]) throws {
        guard !commits.isEmpty else { return }
        let merges = commits.filter(\.isMerge)
        guard merges.isEmpty || commits.count == 1 else {
            throw GitClientError.unsupported("A merge commit can only be cherry-picked on its own.")
        }
        try git.run(Self.noEditor + ["cherry-pick"] + (merges.isEmpty ? [] : ["-m", "1"]) + commits.map(\.hash),
                    environment: Self.noEditorEnvironment)
    }

    /// Moves HEAD back to where it was before the latest move (a commit, a checkout, a reset…). Doing it twice
    /// in a row undoes the undo. Local edits are kept, and the move is refused if it would touch them.
    /// Returns what was undone, e.g. "commit: fix the build".
    @discardableResult
    public func restorePreviousHead() throws -> String {
        let entries = try reflog(maxCount: 2)
        guard entries.count == 2 else { throw GitClientError.unsupported("There is nothing to undo.") }
        let latest = entries[0]
        let moved = "checkout: moving from "
        if latest.message.hasPrefix(moved), let to = latest.message.range(of: " to ") {
            let from = String(latest.message[latest.message.index(latest.message.startIndex, offsetBy: moved.count)..<to.lowerBound])
            try requireName(from, what: "branch")
            try git.run(from.count == 40 ? ["switch", "--detach", from] : ["switch", from])
        } else {
            try git.run(["reset", "--keep", "-q", entries[1].hash])
        }
        return latest.message
    }
}
