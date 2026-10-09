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
