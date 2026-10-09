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

/// The repository opened in the window: its conflicted files and the actions on whole files.
@Observable
final class RepositoryModel {
    let root: URL
    private(set) var files: [ConflictedFile] = []
    var selection: ConflictedFile.ID?
    private(set) var isLoading = false
    private(set) var lastError: String?
    /// One editor per file, kept while the window lives, so switching files never loses resolutions.
    private var editors: [String: EditorModel] = [:]

    var name: String { root.lastPathComponent }
    var selectedFile: ConflictedFile? { files.first { $0.id == selection } }
    var hasUnsavedChanges: Bool { editors.values.contains { $0.hasUnsavedChanges } }
    var unsavedFiles: [String] { editors.filter { $0.value.hasUnsavedChanges }.map(\.key).sorted() }

    private init(root: URL) {
        self.root = root
    }

    /// Fails unless `url` is inside a git repository; the model is rooted at the top-level directory.
    static func open(at url: URL) throws -> RepositoryModel {
        RepositoryModel(root: try Git(directory: url).repositoryRoot())
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            files = try await Self.scan(root: root)
            lastError = nil
            // Forget editors of files that are no longer conflicted, unless they hold unsaved work.
            let listed = Set(files.map(\.id))
            editors = editors.filter { listed.contains($0.key) || $0.value.hasUnsavedChanges }
        } catch {
            lastError = "\(error)"
        }
        if selectedFile == nil {
            selection = files.first?.id
        }
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
    nonisolated private static func scan(root: URL) async throws -> [ConflictedFile] {
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
