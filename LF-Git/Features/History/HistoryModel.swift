import Foundation
import LFKit
import Observation

/// The commit log with its graph, and the files and diff of the selected commit.
@Observable
final class HistoryModel {
    @ObservationIgnored weak var repository: RepositoryModel?

    var pageSize = 200
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
    private var generation = 0
    private var detailGeneration = 0
    /// HEAD when the log was loaded, to notice commits made elsewhere or by the app itself.
    private var loadedHead: String?

    var selectedCommit: GitCommit? { commits.first { $0.id == selection } }

    // MARK: - Loading

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
        if let selection, selectedCommit == nil {
            await select(nil)
        } else if selection == nil {
            await select(commits.first?.id)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading, let client = repository?.client else { return }
        isLoading = true
        let started = generation
        defer { if started == generation { isLoading = false } }
        do {
            let page = try await Self.page(client, count: pageSize, skip: commits.count, all: allBranches)
            guard started == generation else { return }
            commits += page
            graph.append(page)
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

    func selectFile(_ path: String?) async {
        selectedFile = path
        detailGeneration += 1
        let current = detailGeneration
        guard let path, let commit = selectedCommit, let client = repository?.client,
              let change = files.first(where: { $0.path == path }) else {
            diff = nil
            return
        }
        do {
            let loaded = try await Self.loadDiff(client, commit, change)
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
    nonisolated private static func page(_ client: GitClient, count: Int, skip: Int, all: Bool) async throws -> [GitCommit] {
        try client.log(maxCount: count, skip: skip, allBranches: all)
    }

    @concurrent
    nonisolated private static func changedFiles(_ client: GitClient, _ commit: GitCommit) async throws -> [CommitFileChange] {
        try client.changedFiles(in: commit)
    }

    @concurrent
    nonisolated private static func loadDiff(_ client: GitClient, _ commit: GitCommit, _ change: CommitFileChange) async throws -> GitDiffFile {
        try client.diff(of: .commit(commit, path: change.path, originalPath: change.originalPath))
    }
}
