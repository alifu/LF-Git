import Foundation
import LFKit
import Observation

/// One row of the changes list: a path on the staged or the unstaged side. A folder row (`path` ends in `/`) stands
/// for every changed file below it.
nonisolated struct ChangeSelection: Hashable, Sendable {
    let path: String
    let staged: Bool
    var isFolder = false
}

/// Staging, diffs and committing for the repository's work tree.
@Observable
final class ChangesModel {
    @ObservationIgnored weak var repository: RepositoryModel?

    var selection: ChangeSelection?
    private(set) var diff: GitDiffFile?
    /// The selection `diff` was loaded for. The selection can move before the new diff arrives; hunk buttons
    /// are only valid while the two agree.
    private(set) var diffSelection: ChangeSelection?
    private(set) var diffError: String?
    var commitMessage = ""
    /// How diffs are produced; changing it reloads the diff on screen.
    private(set) var options = DiffOptions()
    var noVerify = false
    private(set) var amend = false
    private(set) var isCommitting = false
    /// The message put in the box by turning amend on, so turning it off again can take it back out.
    private var prefilledMessage: String?
    private var diffGeneration = 0
    /// What the loaded diff was made from; a refresh that finds the same change keeps the diff (and the scroll position).
    private var loadedChange: GitChange?
    private var diffIsStale = false

    var status: GitStatus { repository?.status ?? GitStatus() }

    var canCommit: Bool {
        let hasMessage = !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasMessage && (amend || !status.staged.isEmpty) && !isCommitting
    }

    func change(for selection: ChangeSelection) -> GitChange? {
        let list = selection.staged ? status.staged : status.unstaged
        return list.first { $0.path == selection.path }
    }

    // MARK: - Selection and diff

    func select(_ newSelection: ChangeSelection?) async {
        selection = newSelection
        await loadDiff()
    }

    private func loadDiff() async {
        diffGeneration += 1
        let generation = diffGeneration
        diffIsStale = false
        let requested = selection
        guard let requested, let change = change(for: requested), let client = repository?.client else {
            diff = nil
            diffSelection = nil
            loadedChange = nil
            diffError = nil
            return
        }
        let target: DiffTarget = change.kind == .untracked
            ? .untracked(path: change.path)
            : .workingTree(path: change.path, staged: requested.staged)
        do {
            let loaded = try await Self.loadDiff(client, target, options)
            guard generation == diffGeneration else { return } // a newer selection superseded this one
            diff = loaded
            diffSelection = requested
            loadedChange = change
            diffError = nil
        } catch {
            guard generation == diffGeneration else { return }
            diff = nil
            diffSelection = nil
            loadedChange = nil
            diffError = "\(error)"
        }
    }

    /// Called after every refresh: keeps the selection on the same file when it moved between the lists, and
    /// reloads the diff only when the change itself differs (or `reloadDiff` asks for it).
    func statusDidChange(reloadDiff: Bool = false) async {
        if let current = selection, change(for: current) == nil {
            let other = ChangeSelection(path: current.path, staged: !current.staged)
            selection = change(for: other) != nil ? other : nil
        }
        let current = selection.flatMap { change(for: $0) }
        let unchanged = diff != nil && diffSelection == selection && current == loadedChange
        if reloadDiff || diffIsStale || !unchanged {
            await loadDiff()
        }
    }

    func setOptions(_ newOptions: DiffOptions) async {
        guard newOptions != options else { return }
        options = newOptions
        await loadDiff()
    }

    // MARK: - Staging

    func stage(_ paths: [String]) async throws {
        try await mutate { try $0.stage(paths) }
    }

    func unstage(_ paths: [String]) async throws {
        try await mutate { try $0.unstage(paths) }
    }

    /// Unstages a change; a rename needs both of its paths.
    func unstage(_ change: GitChange) async throws {
        try await unstage([change.path] + (change.originalPath.map { [$0] } ?? []))
    }

    func stageAll() async throws {
        try await mutate { try $0.stage(["."]) }
    }

    func unstageAll() async throws {
        try await mutate { try $0.unstage(["."]) }
    }

    func discard(_ changes: [GitChange]) async throws {
        try await mutate { try $0.discard(changes) }
    }

    /// Stages the hunk of an unstaged diff, or unstages the hunk of a staged one. `diff` must be the diff the hunk
    /// was taken from and still the one on screen; otherwise its byte offsets would point into another file.
    func applyHunk(_ hunk: DiffHunk, of diff: GitDiffFile) async throws {
        guard diff === self.diff, let diffSelection else {
            throw GitClientError.unsupported("The diff changed while you were working. Look at it again and retry.")
        }
        try await mutate { try $0.applyHunk(hunk, of: diff, stage: !diffSelection.staged) }
    }

    /// Stages or unstages only these lines of a hunk (see `applyHunk` for why the diff is passed in).
    func applyLines(_ lines: Set<Int>, in hunk: DiffHunk, of diff: GitDiffFile) async throws {
        guard diff === self.diff, let diffSelection, diff.isStageable else {
            throw GitClientError.unsupported("The diff changed while you were working. Look at it again and retry.")
        }
        try await mutate { try $0.applyLines(lines, in: hunk, of: diff, stage: !diffSelection.staged) }
    }

    /// Throws away only these lines of an unstaged diff.
    func discardLines(_ lines: Set<Int>, in hunk: DiffHunk, of diff: GitDiffFile) async throws {
        guard diff === self.diff, diffSelection?.staged == false, diff.isStageable else {
            throw GitClientError.unsupported("The diff changed while you were working. Look at it again and retry.")
        }
        try await mutate { try $0.discardLines(lines, in: hunk, of: diff) }
    }

    private func mutate(_ work: @escaping @Sendable (GitClient) throws -> Void) async throws {
        guard let repository else { return }
        diffIsStale = true
        let client = repository.client
        do {
            try await repository.writeQueue.run { try work(client) }
        } catch {
            await repository.refresh()
            throw error
        }
        await repository.refresh()
    }

    // MARK: - Commit

    func setAmend(_ on: Bool) async {
        guard on != amend else { return }
        amend = on
        if on {
            guard commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let client = repository?.client,
                  let last = try? await Self.lastMessage(client) else { return }
            // The user may have switched amend off or started typing while the message was loading.
            guard amend, commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            commitMessage = last
            prefilledMessage = last
        } else if let prefilled = prefilledMessage, commitMessage == prefilled {
            commitMessage = ""
            prefilledMessage = nil
        }
    }

    /// Commits the staged changes (or amends) and returns the new short hash.
    @discardableResult
    func commit() async throws -> String {
        guard let repository else { return "" }
        isCommitting = true
        defer { isCommitting = false }
        let message = commitMessage
        let amend = amend
        let client = repository.client
        let hash: String
        do {
            let skipHooks = noVerify
            hash = try await repository.writeQueue.run { try client.commit(message: message, amend: amend, noVerify: skipHooks) }
        } catch {
            await repository.refresh()
            throw error
        }
        commitMessage = ""
        self.amend = false
        prefilledMessage = nil
        diffIsStale = true
        await repository.refresh()
        return hash
    }

    // MARK: - Work off the main thread

    @concurrent
    nonisolated private static func loadDiff(_ client: GitClient, _ target: DiffTarget, _ options: DiffOptions) async throws -> GitDiffFile {
        try client.diff(of: target, options: options)
    }

    @concurrent
    nonisolated private static func lastMessage(_ client: GitClient) async throws -> String? {
        try client.lastCommitMessage()
    }
}
