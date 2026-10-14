import Foundation
import LFKit

/// Actions shared by the lists: questions, the commit clipboard and undo.
extension RepositoryModel {
    func ask(_ prompt: PendingPrompt) {
        self.prompt = prompt
    }

    func confirm(_ confirmation: PendingConfirmation) {
        self.confirmation = confirmation
    }

    // MARK: Asking first

    /// Pulls. Merge and rebase change the branch in ways a fast-forward does not, so they say what will happen and wait for a yes.
    func requestPull(_ strategy: PullStrategy, app: AppModel) {
        let branch = status.branch ?? "the current branch"
        let upstream = status.upstream ?? "its upstream"
        switch strategy {
        case .fastForwardOnly:
            app.run { try await self.pull(.fastForwardOnly) }
        case .merge:
            confirm(PendingConfirmation(title: "Pull and merge ‘\(upstream)’ into ‘\(branch)’?",
                                        message: "Fetches \(upstream) and merges it into \(branch); a merge commit is created when the branches diverged.",
                                        confirmTitle: "Pull and Merge", isDestructive: false) { app.run { try await self.pull(.merge) } })
        case .rebase:
            confirm(PendingConfirmation(title: "Pull and rebase ‘\(branch)’ onto ‘\(upstream)’?",
                                        message: "Fetches \(upstream) and replays the commits of \(branch) on top of it, which rewrites those commits.",
                                        confirmTitle: "Pull and Rebase", isDestructive: false) { app.run { try await self.pull(.rebase) } })
        }
    }

    /// Cherry-picks the copied commits after saying which and where.
    func requestPaste(app: AppModel) {
        let count = copiedCommits.count
        guard count > 0 else { return }
        let branch = status.branch ?? "the current HEAD"
        let list = copiedCommits.prefix(5).map { "• \($0.shortHash) \($0.subject)" }.joined(separator: "\n")
        confirm(PendingConfirmation(title: "Cherry-pick \(count) commit\(count == 1 ? "" : "s") onto ‘\(branch)’?",
                                    message: list + (count > 5 ? "\n… and \(count - 5) more" : ""),
                                    confirmTitle: "Cherry-Pick", isDestructive: false) { app.run { try await self.pasteCopiedCommits() } })
    }

    // MARK: Cherry-pick clipboard

    func copyCommits(_ commits: [GitCommit]) {
        let known = Set(copiedCommits.map(\.hash))
        copiedCommits = copiedCommits + commits.filter { !known.contains($0.hash) }
    }

    func clearCopiedCommits() {
        copiedCommits = []
    }

    /// Cherry-picks the copied commits, oldest first, and empties the clipboard when it worked.
    func pasteCopiedCommits() async throws {
        let copied = copiedCommits
        try await perform("Cherry-picking \(copied.count) commit\(copied.count == 1 ? "" : "s")…") { client, _ in
            try client.cherryPick(try client.sortedOldestFirst(copied))
        }
        copiedCommits = []
    }

    // MARK: Undo

    /// Moves HEAD back to where it was before the latest move (the same call redoes it).
    func undoHeadMove() async throws {
        let undone = ResultBox<String>()
        try await perform("Undoing…") { client, _ in undone.value = try client.restorePreviousHead() }
        undoneMessage = undone.value
    }

    func message(of commit: GitCommit) async throws -> String {
        let client = client
        return try await Self.readMessage(client, commit)
    }

    @concurrent
    nonisolated private static func readMessage(_ client: GitClient, _ commit: GitCommit) async throws -> String {
        try client.message(of: commit)
    }

    /// The commit behind a reflog entry or a tag, for the viewer.
    func commit(for hash: String) async -> GitCommit? {
        let client = client
        return await Self.lookUp(client, hash)
    }

    @concurrent
    nonisolated private static func lookUp(_ client: GitClient, _ hash: String) async -> GitCommit? {
        try? client.commit(for: hash)
    }
}

/// Carries a result out of a `@Sendable` closure that runs on another thread.
nonisolated final class ResultBox<Value>: @unchecked Sendable {
    var value: Value?
}
