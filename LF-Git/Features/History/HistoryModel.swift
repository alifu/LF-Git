import Foundation
import LFKit
import Observation

/// The commit log with its graph, and the files and diff of the selected commit.
@Observable
final class HistoryModel {
    @ObservationIgnored weak var repository: RepositoryModel?

    /// Where the commits come from.
    enum Source: Sendable {
        /// The log of HEAD, or of another branch/tag/commit.
        case log(revision: String?)
        /// A fixed list: one stash, one tag, one reflog entry.
        case fixed([GitCommit])
    }

    var pageSize = 200
    private(set) var source: Source = .log(revision: nil)
    /// Search text and path of the log, applied on top of the source.
    var filter = GitLogFilter()
    private(set) var commits: [GitCommit] = []
    private(set) var graph = CommitGraph()
    private(set) var hasMore = true
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var allBranches = false
    private(set) var selection: GitCommit.ID?
    private(set) var files: [CommitFileChange] = []
    private(set) var selectedFile: String?
    private(set) var diff: GitDiffFile?
    private(set) var detailError: String?
    /// Two revisions being compared instead of one commit.
    struct Comparison: Equatable, Sendable {
        let from: String
        let to: String
        var title: String { "\(String(from.prefix(10)))  →  \(String(to.prefix(10)))" }
    }

    private(set) var comparison: Comparison?
    /// Who changed each line of `selectedFile`, when the blame view is on.
    private(set) var blame: [GitBlameLine]?
    private(set) var blameFile: String?
    private var generation = 0
    private var detailGeneration = 0
    /// HEAD when the log was loaded, to notice commits made elsewhere or by the app itself.
    private var loadedHead: String?

    var selectedCommit: GitCommit? { commits.first { $0.id == selection } }

    // MARK: - Loading

    /// Shows another list and loads it.
    func show(_ newSource: Source) async {
        source = newSource
        await reload()
    }

    /// Starts again from the newest commit.
    func reload() async {
        generation += 1
        isLoading = false // a page of the previous generation may still be in flight; it will be dropped
        commits = []
        graph = CommitGraph()
        hasMore = true
        loadedHead = repository?.status.commitHash
        await loadMore()
        hasLoaded = true
        if selection != nil, selectedCommit == nil {
            await select(nil)
        } else if selection == nil {
            await select(commits.first?.id)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading, let client = repository?.client else { return }
        if case .fixed(let list) = source {
            commits = list
            hasMore = false
            return
        }
        isLoading = true
        let started = generation
        defer { if started == generation { isLoading = false } }
        var effective = filter
        if case .log(let revision) = source { effective.revision = revision }
        do {
            let page = try await Self.page(client, count: pageSize, skip: commits.count, all: allBranches && effective.revision == nil,
                                           filter: effective)
            guard started == generation else { return }
            commits += page
            if filter.isEmpty { graph.append(page) }
            hasMore = page.count == pageSize
        } catch {
            guard started == generation else { return }
            hasMore = false
            detailError = "\(error)"
        }
    }

    /// After a refresh: a changed HEAD means new commits, so a loaded log starts over.
    func repositoryDidChange() async {
        guard hasLoaded, repository?.status.commitHash != loadedHead else { return }
        await reload()
    }

    // MARK: - Detail

    func select(_ id: GitCommit.ID?) async {
        selection = id
        comparison = nil
        blame = nil
        files = []
        selectedFile = nil
        diff = nil
        detailGeneration += 1
        let current = detailGeneration
        guard let commit = selectedCommit, let client = repository?.client else { return }
        do {
            let changed = try await Self.changedFiles(client, commit)
            guard current == detailGeneration else { return }
            files = changed
            detailError = nil
            await selectFile(changed.first?.path)
        } catch {
            guard current == detailGeneration else { return }
            detailError = "\(error)"
        }
    }

    /// Lists what differs between two revisions and shows the first file.
    func compare(from: String, to: String) async {
        guard let client = repository?.client else { return }
        selection = nil
        blame = nil
        files = []
        selectedFile = nil
        diff = nil
        let comparison = Comparison(from: from, to: to)
        self.comparison = comparison
        detailGeneration += 1
        let current = detailGeneration
        do {
            let changed = try await Self.changedFiles(client, from: from, to: to)
            guard current == detailGeneration else { return }
            files = changed
            detailError = nil
            await selectFile(changed.first?.path)
        } catch {
            guard current == detailGeneration else { return }
            detailError = "\(error)"
        }
    }

    /// Shows the blame of the selected file as of the selected commit, or switches back to the diff.
    func showBlame(_ on: Bool) async {
        guard on, let path = selectedFile, let commit = selectedCommit, let client = repository?.client else {
            blame = nil
            return
        }
        detailGeneration += 1
        let current = detailGeneration
        do {
            let lines = try await Self.blame(client, path: path, revision: commit.hash)
            guard current == detailGeneration else { return }
            blame = lines
            blameFile = path
            detailError = nil
        } catch {
            guard current == detailGeneration else { return }
            blame = nil
            detailError = "\(error)"
        }
    }

    func selectFile(_ path: String?) async {
        selectedFile = path
        blame = nil
        detailGeneration += 1
        let current = detailGeneration
        guard let path, let client = repository?.client, let change = files.first(where: { $0.path == path }) else {
            diff = nil
            return
        }
        do {
            let loaded: GitDiffFile
            if let comparison {
                loaded = try await Self.loadRangeDiff(client, comparison, change)
            } else if let commit = selectedCommit {
                loaded = try await Self.loadDiff(client, commit, change)
            } else {
                diff = nil
                return
            }
            guard current == detailGeneration else { return }
            diff = loaded
            detailError = nil
        } catch {
            guard current == detailGeneration else { return }
            diff = nil
            detailError = "\(error)"
        }
    }

    // MARK: - Work off the main thread

    @concurrent
    nonisolated private static func page(_ client: GitClient, count: Int, skip: Int, all: Bool,
                                         filter: GitLogFilter) async throws -> [GitCommit] {
        try client.log(maxCount: count, skip: skip, allBranches: all, filter: filter)
    }

    @concurrent
    nonisolated private static func changedFiles(_ client: GitClient, _ commit: GitCommit) async throws -> [CommitFileChange] {
        try client.changedFiles(in: commit)
    }

    @concurrent
    nonisolated private static func changedFiles(_ client: GitClient, from: String, to: String) async throws -> [CommitFileChange] {
        try client.changedFiles(from: from, to: to)
    }

    @concurrent
    nonisolated private static func loadRangeDiff(_ client: GitClient, _ comparison: Comparison,
                                                  _ change: CommitFileChange) async throws -> GitDiffFile {
        try client.diff(of: .range(from: comparison.from, to: comparison.to, path: change.path, originalPath: change.originalPath))
    }

    @concurrent
    nonisolated private static func blame(_ client: GitClient, path: String, revision: String) async throws -> [GitBlameLine] {
        try client.blame(path: path, revision: revision)
    }

    @concurrent
    nonisolated private static func loadDiff(_ client: GitClient, _ commit: GitCommit, _ change: CommitFileChange) async throws -> GitDiffFile {
        try client.diff(of: .commit(commit, path: change.path, originalPath: change.originalPath))
    }
}
