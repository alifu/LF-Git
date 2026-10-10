import Foundation
import LFKit
import Observation

/// One unmerged path of the repository.
nonisolated struct ConflictedFile: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text
        case project
        case binary
    }

    let path: String
    let kind: Kind
    let conflictCount: Int
    let size: Int64?
    /// Why the file could not be read, if it could not.
    let problem: String?

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }
}

/// The parts of a repository window.
enum RepositorySection: String, CaseIterable, Identifiable {
    case changes = "Changes"
    case branches = "Branches"
    case history = "History"
    case stash = "Stash"
    case tags = "Tags"
    case remotes = "Remotes"
    case reflog = "Reflog"
    case worktrees = "Worktrees"
    case submodules = "Submodules"
    case conflicts = "Conflicts"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .changes: "plus.forwardslash.minus"
        case .branches: "arrow.triangle.branch"
        case .history: "clock.arrow.circlepath"
        case .stash: "tray.full"
        case .tags: "tag"
        case .remotes: "externaldrive.connected.to.line.below"
        case .reflog: "arrow.uturn.backward.circle"
        case .worktrees: "square.stack.3d.up"
        case .submodules: "shippingbox"
        case .conflicts: "exclamationmark.triangle"
        }
    }
}

/// A question with a text answer, shown as an alert by the repository window.
struct PendingPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var placeholder = ""
    var initialText = ""
    let confirmTitle: String
    let action: (String) -> Void
}

/// What a stopped merge/rebase looks like, to tell "this call hit conflicts" from "this call failed".
nonisolated struct ConflictState: Equatable, Sendable {
    let operation: GitOperation?
    let files: [String]
    let head: String?
}

/// A multi-line message to write (a commit message, a stash name…).
struct PendingMessageEdit: Identifiable {
    let id = UUID()
    let title: String
    let initialText: String
    let confirmTitle: String
    let action: (String) -> Void
}

/// A yes/no question before something that cannot be undone.
struct PendingConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    var isDestructive = true
    let action: () -> Void
}

/// Everything read from git in one pass, off the main thread.
nonisolated struct RepositorySnapshot: Sendable {
    let files: [ConflictedFile]
    let status: GitStatus
    let branches: [GitBranch]
    let operation: GitOperation?
    let stashes: [GitStash]
    let tags: [GitTag]
    let remotes: [GitRemote]
    let reflog: [GitReflogEntry]
    let worktrees: [GitWorktree]
    let submodules: [GitSubmodule]
    let isBisecting: Bool
    let bisectCandidate: String?
}

/// The repository opened in the window: git state, conflicted files and the actions on whole files.
@Observable
final class RepositoryModel {
    let root: URL
    let client: GitClient
    /// Every git command the user's actions run, for the command log.
    let commandLog = GitCommandLog()
    /// Everything that writes to the repository runs here, one command at a time.
    let writeQueue = GitWriteQueue()
    let changes: ChangesModel
    let history: HistoryModel
    /// The commits of the branch selected in the Branches section.
    let branchHistory: HistoryModel
    /// One commit shown on its own: a stash, a tag or a reflog entry.
    let commitViewer: HistoryModel
    private(set) var files: [ConflictedFile] = []
    var selection: ConflictedFile.ID?
    private(set) var status = GitStatus()
    private(set) var branches: [GitBranch] = []
    private(set) var operation: GitOperation?
    private(set) var stashes: [GitStash] = []
    private(set) var tags: [GitTag] = []
    private(set) var remotes: [GitRemote] = []
    private(set) var reflog: [GitReflogEntry] = []
    private(set) var worktrees: [GitWorktree] = []
    private(set) var submodules: [GitSubmodule] = []
    /// Everything that happened in this window, newest last: git commands, actions and problems.
    private(set) var activity: [LogEvent] = []
    private var activityCounter = 0
    /// Commits copied for a later cherry-pick, oldest first.
    var copiedCommits: [GitCommit] = []
    var prompt: PendingPrompt?
    var messageEdit: PendingMessageEdit?
    // What is selected in each section's list.
    var branchSelection: String?
    var stashSelection: String?
    var tagSelection: String?
    var remoteSelection: String?
    var reflogSelection: String?
    var worktreeSelection: String?
    var submoduleSelection: String?
    /// First side of a comparison, chosen with "Select for Compare".
    var compareBase: GitCommit?
    /// The commit marked as bad / good for a bisect that has not started yet.
    var bisectBad: GitCommit?
    var bisectGood: GitCommit?
    private(set) var isBisecting = false
    private(set) var bisectCandidate: String?
    var confirmation: PendingConfirmation?
    var showsLogPanel = false
    var showsPalette = false
    var showsHelp = false
    var section: RepositorySection = .changes
    private var hasChosenSection = false
    private var refreshGeneration = 0
    private(set) var isLoading = false
    /// A network or branch operation is running; the toolbar shows what it is.
    private(set) var busyTitle: String?
    private(set) var lastError: String?
    /// One editor per file, kept while the window lives, so switching files never loses resolutions.
    private var editors: [String: EditorModel] = [:]

    @ObservationIgnored private var activeCancellation: GitCancellation?
    @ObservationIgnored private var logObserver: UUID?
    @ObservationIgnored private var watcher: RepositoryWatcher?
    /// The running action can be stopped (fetch, pull, push…).
    private(set) var isCancellable = false
    /// What `undo` would take back, for the menu.
    var undoneMessage: String?

    var isBusy: Bool { busyTitle != nil }
    var name: String { root.lastPathComponent }
    var currentBranch: GitBranch? { branches.first { $0.isCurrent && !$0.isRemote } }
    var selectedFile: ConflictedFile? { files.first { $0.id == selection } }
    var hasUnsavedChanges: Bool { editors.values.contains { $0.hasUnsavedChanges } }
    var unsavedFiles: [String] { editors.filter { $0.value.hasUnsavedChanges }.map(\.key).sorted() }

    private init(root: URL) {
        self.root = root
        client = GitClient(directory: root, log: commandLog)
        changes = ChangesModel()
        history = HistoryModel()
        branchHistory = HistoryModel()
        commitViewer = HistoryModel()
        changes.repository = self
        history.repository = self
        branchHistory.repository = self
        commitViewer.repository = self
        logObserver = commandLog.observe { [weak self] entry in
            Task { @MainActor in self?.append(entry) }
        }
    }

    /// Follows edits made outside the app (an editor, a terminal) by refreshing when files change.
    /// Only the real window does this; the model alone stays predictable for tests.
    func startWatching() {
        guard watcher == nil else { return }
        watcher = RepositoryWatcher(root: root) { [weak self] in
            Task { @MainActor in
                guard let self, !self.isBusy else { return }
                self.record(.info, "Files changed outside the app: reloaded")
                await self.refresh()
            }
        }
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    deinit {
        if let logObserver { commandLog.stopObserving(logObserver) }
    }

    private static let activityCapacity = 500

    /// Adds a line to the log panel.
    func record(_ kind: LogEvent.Kind, _ text: String, succeeded: Bool = true, duration: TimeInterval? = nil, date: Date = Date()) {
        activityCounter += 1
        activity.append(LogEvent(id: activityCounter, date: date, kind: kind, text: text, succeeded: succeeded, duration: duration))
        if activity.count > Self.activityCapacity { activity.removeFirst(activity.count - Self.activityCapacity) }
    }

    func clearActivity() {
        activity = []
    }

    private func append(_ entry: GitCommandEntry) {
        record(.git, entry.command, succeeded: entry.succeeded, duration: entry.duration, date: entry.date)
    }

    /// Fails unless `url` is inside a git repository; the model is rooted at the top-level directory.
    static func open(at url: URL) throws -> RepositoryModel {
        RepositoryModel(root: try Git(directory: url).repositoryRoot())
    }

    /// Reads the repository again. The newest refresh wins: an older, slower one is dropped when it finishes.
    /// - Parameter reloadDiffs: also reload the diff on screen, even if its change looks the same.
    func refresh(reloadDiffs: Bool = false) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoading = true
        defer { if generation == refreshGeneration { isLoading = false } }
        do {
            let snapshot = try await Self.snapshot(root: root)
            guard generation == refreshGeneration else { return }
            files = snapshot.files
            status = snapshot.status
            branches = snapshot.branches
            operation = snapshot.operation
            stashes = snapshot.stashes
            tags = snapshot.tags
            remotes = snapshot.remotes
            reflog = snapshot.reflog
            worktrees = snapshot.worktrees
            submodules = snapshot.submodules
            isBisecting = snapshot.isBisecting
            bisectCandidate = snapshot.bisectCandidate
            lastError = nil
            if !hasChosenSection {
                hasChosenSection = true
                section = files.isEmpty ? .changes : .conflicts
            }
            // Forget editors of files that are no longer conflicted, unless they hold unsaved work.
            let listed = Set(files.map(\.id))
            editors = editors.filter { listed.contains($0.key) || $0.value.hasUnsavedChanges }
        } catch {
            guard generation == refreshGeneration else { return }
            lastError = "\(error)"
        }
        if selectedFile == nil {
            selection = files.first?.id
        }
        await changes.statusDidChange(reloadDiff: reloadDiffs)
        await history.repositoryDidChange()
    }

    // MARK: - Branches, operations and remotes

    /// Runs git work off the main thread with a title in the toolbar, then refreshes. A failure refreshes too
    /// (a rebase that stops on the next conflict has changed the state) and is rethrown.
    /// - Parameters:
    ///   - cancellable: the toolbar offers a Cancel button, which stops git (`GitError.cancelled`).
    ///   - serialized: wait for other writing commands. Network commands that only touch refs pass false,
    ///     so staging stays possible during a long fetch.
    func perform(_ title: String, cancellable: Bool = false, serialized: Bool = true,
                 _ work: @escaping @Sendable (GitClient, GitCancellation) throws -> Void) async throws {
        busyTitle = title
        let actionName = title.trimmingCharacters(in: CharacterSet(charactersIn: "…. "))
        let started = Date()
        record(.action, "Started: \(actionName)")
        let token = GitCancellation()
        activeCancellation = cancellable ? token : nil
        isCancellable = cancellable
        defer {
            busyTitle = nil
            isCancellable = false
            activeCancellation = nil
        }
        let client = client
        let before = ConflictState(operation: operation, files: files.map(\.id), head: status.commitHash)
        do {
            if serialized {
                try await writeQueue.run { try work(client, token) }
            } else {
                try await Self.unqueued { try work(client, token) }
            }
        } catch {
            await refresh()
            // A merge, rebase or cherry-pick that stops on conflicts is not a failure: the banner takes over.
            // Only when this very call moved things: a failure while an old conflict was already waiting is real.
            let after = ConflictState(operation: operation, files: files.map(\.id), head: status.commitHash)
            if after.operation != nil, !files.isEmpty, after != before, error is GitError, (error as? GitError) != .cancelled {
                record(.info, "\(actionName) stopped on conflicts: resolve them, then Continue or Abort")
                return
            }
            if (error as? GitError) == .cancelled {
                record(.info, "Cancelled: \(actionName)")
            } else {
                record(.error, "Failed: \(actionName): \(error)", succeeded: false)
            }
            throw error
        }
        record(.action, "Finished: \(actionName)", duration: Date().timeIntervalSince(started))
        await refresh()
    }

    @concurrent
    nonisolated private static func unqueued(_ work: @Sendable () throws -> Void) async throws {
        try work()
    }

    /// Stops the running fetch, pull or push.
    func cancelBusy() {
        activeCancellation?.cancel()
    }

    func switchBranch(_ name: String) async throws {
        try await perform("Switching to \(name)…") { client, _ in try client.switchBranch(name) }
    }

    func createBranch(_ name: String, from startPoint: String? = nil) async throws {
        try await perform("Creating \(name)…") { client, _ in try client.createBranch(name, from: startPoint) }
    }

    func deleteBranch(_ name: String, force: Bool = false) async throws {
        try await perform("Deleting \(name)…") { client, _ in try client.deleteBranch(name, force: force) }
    }

    func fetch() async throws {
        try await perform("Fetching…", cancellable: true, serialized: false) { client, token in try client.fetch(cancellation: token) }
    }

    func pull(_ strategy: PullStrategy = .fastForwardOnly) async throws {
        try await perform("Pulling…", cancellable: true) { client, token in try client.pull(strategy, cancellation: token) }
    }

    func push(force: Bool = false) async throws {
        try await perform("Pushing…", cancellable: true, serialized: false) { client, token in
            try client.push(force: force, cancellation: token)
        }
    }

    func continueOperation() async throws {
        guard let operation else { return }
        try await perform("Continuing \(operation.title.lowercased())…") { client, _ in try client.continueOperation(operation) }
    }

    func abortOperation() async throws {
        guard let operation else { return }
        try await perform("Aborting \(operation.title.lowercased())…") { client, _ in try client.abort(operation) }
        editors.removeAll()
    }

    func skipOperation() async throws {
        guard let operation else { return }
        try await perform("Skipping…") { client, _ in try client.skip(operation) }
    }

    /// The editor of a conflicted text file, opened once and then reused.
    func editor(for path: String) async throws -> EditorModel {
        if let editor = editors[path] {
            return editor
        }
        let editor = try await EditorModel.load(path: root.appendingPathComponent(path).path, displayPath: path, repository: root)
        if let raced = editors[path] { // another view opened it meanwhile
            return raced
        }
        editors[path] = editor
        return editor
    }

    /// Stages a file whose conflicts were resolved some other way (no markers left).
    func markResolved(_ path: String) async throws {
        try await Self.stage(path, root: root)
        editors[path] = nil
        await refresh()
    }

    /// Binary files: keep one whole side and stage it.
    func takeSide(_ side: Git.Side, of path: String) async throws {
        try await Self.checkout(side, path: path, root: root)
        await refresh()
    }

    /// Project files: re-merge object by object from the index; a clean result is staged.
    func remergeProject(_ path: String) async throws -> ProjectRemerge.Outcome {
        let outcome = try await Self.remerge(path, root: root)
        editors[path] = nil // the file was rewritten; its old editor no longer matches it
        await refresh()
        return outcome
    }

    func absolutePath(of file: ConflictedFile) -> String {
        root.appendingPathComponent(file.path).path
    }

    // MARK: - Work off the main thread

    @concurrent
    nonisolated private static func snapshot(root: URL) async throws -> RepositorySnapshot {
        let client = GitClient(directory: root)
        let hasSubmodules = FileManager.default.fileExists(atPath: root.appendingPathComponent(".gitmodules").path)
        return RepositorySnapshot(
            files: try scan(root: root), status: try client.status(), branches: try client.branches(),
            operation: try client.operation(), stashes: try client.stashes(), tags: try client.tags(),
            remotes: try client.remotes(), reflog: try client.reflog(maxCount: 200),
            worktrees: try client.worktrees(), submodules: hasSubmodules ? try client.submodules() : [],
            isBisecting: try client.isBisecting(), bisectCandidate: try client.bisectCandidate()
        )
    }

    nonisolated private static func scan(root: URL) throws -> [ConflictedFile] {
        let git = Git(directory: root)
        return try git.conflictedPaths().map { path in
            let absolute = root.appendingPathComponent(path).path
            let size = (try? FileManager.default.attributesOfItem(atPath: absolute)[.size] as? Int64) ?? nil
            do {
                if try LFFileProbe(path: absolute).kind == .binary {
                    return ConflictedFile(path: path, kind: .binary, conflictCount: 0, size: size, problem: nil)
                }
                let count = try LFDocument(path: absolute, markerSize: git.markerSize(forPath: absolute)).info.conflictCount
                let kind: ConflictedFile.Kind = MergeStrategy.forPath(path) == .pbxproj ? .project : .text
                return ConflictedFile(path: path, kind: kind, conflictCount: count, size: size, problem: nil)
            } catch {
                return ConflictedFile(path: path, kind: .text, conflictCount: 0, size: size, problem: "\(error)")
            }
        }
    }

    @concurrent
    nonisolated private static func checkout(_ side: Git.Side, path: String, root: URL) async throws {
        let git = Git(directory: root)
        try git.checkout(side, path: path)
        try git.stage([path])
    }

    @concurrent
    nonisolated private static func stage(_ path: String, root: URL) async throws {
        try Git(directory: root).stage([path])
    }

    @concurrent
    nonisolated private static func remerge(_ path: String, root: URL) async throws -> ProjectRemerge.Outcome {
        try ProjectRemerge(root: root).run(path, options: ProjectRemerge.Options(backup: true, stage: true))
    }
}
