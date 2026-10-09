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
    case history = "History"
    case conflicts = "Conflicts"

    var id: String { rawValue }
}

/// Everything read from git in one pass, off the main thread.
nonisolated struct RepositorySnapshot: Sendable {
    let files: [ConflictedFile]
    let status: GitStatus
    let branches: [GitBranch]
    let operation: GitOperation?
}

/// The repository opened in the window: git state, conflicted files and the actions on whole files.
@Observable
final class RepositoryModel {
    let root: URL
    let client: GitClient
    /// Everything that writes to the repository runs here, one command at a time.
    let writeQueue = GitWriteQueue()
    let changes: ChangesModel
    let history: HistoryModel
    private(set) var files: [ConflictedFile] = []
    var selection: ConflictedFile.ID?
    private(set) var status = GitStatus()
    private(set) var branches: [GitBranch] = []
    private(set) var operation: GitOperation?
    var section: RepositorySection = .changes
    private var hasChosenSection = false
    private var refreshGeneration = 0
    private(set) var isLoading = false
    /// A network or branch operation is running; the toolbar shows what it is.
    private(set) var busyTitle: String?
    private(set) var lastError: String?
    /// One editor per file, kept while the window lives, so switching files never loses resolutions.
    private var editors: [String: EditorModel] = [:]

    var isBusy: Bool { busyTitle != nil }
    var name: String { root.lastPathComponent }
    var currentBranch: GitBranch? { branches.first { $0.isCurrent && !$0.isRemote } }
    var selectedFile: ConflictedFile? { files.first { $0.id == selection } }
    var hasUnsavedChanges: Bool { editors.values.contains { $0.hasUnsavedChanges } }
    var unsavedFiles: [String] { editors.filter { $0.value.hasUnsavedChanges }.map(\.key).sorted() }

    private init(root: URL) {
        self.root = root
        client = GitClient(directory: root)
        changes = ChangesModel()
        history = HistoryModel()
        changes.repository = self
        history.repository = self
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
    private func perform(_ title: String, _ work: @escaping @Sendable (GitClient) throws -> Void) async throws {
        busyTitle = title
        defer { busyTitle = nil }
        let client = client
        do {
            try await writeQueue.run { try work(client) }
        } catch {
            await refresh()
            throw error
        }
        await refresh()
    }

    func switchBranch(_ name: String) async throws {
        try await perform("Switching to \(name)…") { try $0.switchBranch(name) }
    }

    func createBranch(_ name: String, from startPoint: String? = nil) async throws {
        try await perform("Creating \(name)…") { try $0.createBranch(name, from: startPoint) }
    }

    func deleteBranch(_ name: String, force: Bool = false) async throws {
        try await perform("Deleting \(name)…") { try $0.deleteBranch(name, force: force) }
    }

    func fetch() async throws {
        try await perform("Fetching…") { try $0.fetch() }
    }

    func pull(_ strategy: PullStrategy = .fastForwardOnly) async throws {
        try await perform("Pulling…") { try $0.pull(strategy) }
    }

    func push() async throws {
        try await perform("Pushing…") { try $0.push() }
    }

    func continueOperation() async throws {
        guard let operation else { return }
        try await perform("Continuing \(operation.title.lowercased())…") { try $0.continueOperation(operation) }
    }

    func abortOperation() async throws {
        guard let operation else { return }
        try await perform("Aborting \(operation.title.lowercased())…") { try $0.abort(operation) }
        editors.removeAll()
    }

    func skipOperation() async throws {
        guard let operation else { return }
        try await perform("Skipping…") { try $0.skip(operation) }
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
        return RepositorySnapshot(
            files: try scan(root: root), status: try client.status(), branches: try client.branches(),
            operation: try client.operation()
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
