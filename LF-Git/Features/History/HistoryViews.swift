import LFKit
import SwiftUI

/// The History section's list: a filter bar over the commits with their graph.
struct HistorySidebar: View {
    let repository: RepositoryModel
    let app: AppModel
    @State private var query = ""
    @State private var field: FilterField = .message

    private var history: HistoryModel { repository.history }

    enum FilterField: String, CaseIterable, Identifiable {
        case message = "Message"
        case author = "Author"
        case path = "File"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            CommitListView(repository: repository, app: app, model: history)
        }
        .task {
            if !history.hasLoaded { await history.reload() }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.theme(.textSubtle))
                TextField("Filter commits", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit(applyFilter)
                    .accessibilityIdentifier("history-filter")
                if !query.isEmpty || !history.filter.isEmpty {
                    Button {
                        query = ""
                        applyFilter()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear the filter")
                }
                Picker("Search in", selection: $field) {
                    ForEach(FilterField.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: field) { applyFilter() }
            }
            HStack {
                Toggle("All branches", isOn: Binding(
                    get: { history.allBranches },
                    set: { history.allBranches = $0; Task { await history.reload() } }
                ))
                .toggleStyle(.checkbox)
                .font(.callout)
                .accessibilityIdentifier("all-branches")
                Spacer()
                Button {
                    Task { await history.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload history")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func applyFilter() {
        let text = query.trimmingCharacters(in: .whitespaces)
        var filter = GitLogFilter()
        if !text.isEmpty {
            switch field {
            case .message: filter.message = text
            case .author: filter.author = text
            case .path:
                filter.path = text
                filter.followRenames = true
            }
        }
        history.filter = filter
        Task { await history.reload() }
    }
}

/// Commits with the graph and a context menu of everything that can be done to a commit.
struct CommitListView: View {
    let repository: RepositoryModel
    let app: AppModel
    let model: HistoryModel
    @State private var selected: Set<GitCommit.ID> = []

    static let rowHeight: CGFloat = 38

    var body: some View {
        List(selection: $selected) {
            ForEach(Array(model.commits.enumerated()), id: \.element.id) { index, commit in
                CommitRow(commit: commit, row: model.graph.rows.indices.contains(index) ? model.graph.rows[index] : nil,
                          currentBranch: repository.status.branch,
                          isCopied: repository.copiedCommits.contains { $0.hash == commit.hash })
                    .tag(commit.id)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .contextMenu {
                        let picked = selected.contains(commit.id) && selected.count > 1
                            ? model.commits.filter { selected.contains($0.id) } : [commit]
                        CommitContextMenu(repository: repository, app: app, model: model, commits: picked)
                    }
                    .onAppear {
                        if index >= model.commits.count - 20 {
                            Task { await model.loadMore() }
                        }
                    }
            }
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, Self.rowHeight)
        .accessibilityIdentifier("history-list")
        .onChange(of: selected) {
            if selected.count == 1, let only = selected.first, only != model.selection {
                Task { await model.select(only) }
            }
        }
        .onChange(of: model.selection) {
            if let id = model.selection, !(selected.count > 1 && selected.contains(id)) { selected = [id] }
        }
        .overlay {
            if model.hasLoaded && model.commits.isEmpty {
                ContentUnavailableView(model.filter.isEmpty ? "No commits yet" : "No matching commits",
                                       systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

private struct CommitRow: View {
    let commit: GitCommit
    let row: CommitGraph.Row?
    let currentBranch: String?
    let isCopied: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let row {
                GraphRowView(row: row, isMerge: commit.isMerge)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    ForEach(commit.refs.prefix(3), id: \.self) { ref in
                        Text(ref)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.theme(ref == currentBranch ? .accent : .accentSubtle)))
                            .foregroundStyle(.theme(ref == currentBranch ? .onAccent : .accentText))
                            .lineLimit(1)
                    }
                    Text(commit.subject).lineLimit(1)
                    if isCopied {
                        Image(systemName: "doc.on.doc.fill").font(.caption).foregroundStyle(.theme(.info))
                            .accessibilityLabel("copied for cherry-pick")
                    }
                }
                Text("\(commit.authorName) · \(commit.date.formatted(.relative(presentation: .named))) · \(commit.shortHash)")
                    .font(.caption)
                    .foregroundStyle(.theme(.textSubtle))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: CommitListView.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("commit-\(commit.subject)")
    }
}

/// The selected commit (or comparison): who and when, its files, and the diff or blame of one file.
struct HistoryDetailView: View {
    let repository: RepositoryModel
    let app: AppModel
    let model: HistoryModel
    @State private var lineSelection: Set<Int> = []
    @AppStorage("diff.showsBlame") private var showsBlame = true

    var body: some View {
        Group {
            if let commit = model.selectedCommit {
                detail { header(commit) }
            } else if let comparison = model.comparison {
                detail { comparisonHeader(comparison) }
            } else {
                // The same layout as with a commit, just empty, so the view never collapses to half a window.
                detail { emptyHeader }
            }
        }
        .background(.theme(.background))
    }

    private func detail<Header: View>(@ViewBuilder header: () -> Header) -> some View {
        VStack(spacing: 0) {
            header()
            Divider()
            VSplitView {
                fileList
                    .frame(minHeight: 90, idealHeight: 130)
                content
                    .frame(minHeight: 160)
            }
        }
    }

    private var canRewrite: Bool {
        if case .log(let revision) = model.source { return revision == nil && repository.operation == nil }
        return false
    }

    private var emptyHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No commit selected").font(.headline).foregroundStyle(.theme(.textSubtle))
            Text("Pick a commit to see its files, diff and blame.").font(.callout).foregroundStyle(.theme(.textSubtle))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.theme(.surfaceRaised))
    }

    private func comparisonHeader(_ comparison: HistoryModel.Comparison) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Comparing").font(.headline).foregroundStyle(.theme(.text))
            Text(comparison.title).font(.callout.monospaced()).foregroundStyle(.theme(.textSubtle))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.theme(.surfaceRaised))
    }

    private func header(_ commit: GitCommit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(commit.subject).font(.headline).foregroundStyle(.theme(.text)).textSelection(.enabled)
            Text("\(commit.authorName) <\(commit.authorEmail)> · \(commit.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.callout)
                .foregroundStyle(.theme(.textSubtle))
            Text(commit.hash + (commit.parents.isEmpty ? "" : "  ←  " + commit.parents.map { String($0.prefix(7)) }.joined(separator: ", ")))
                .font(.caption.monospaced())
                .foregroundStyle(.theme(.textSubtle))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.theme(.surfaceRaised))
    }

    private var fileList: some View {
        List(selection: Binding(get: { model.selectedFile }, set: { path in Task { await model.selectFile(path) } })) {
            ForEach(model.files) { file in
                HStack(spacing: 8) {
                    Text(file.status.symbol)
                        .font(.caption.monospaced().weight(.bold))
                        .frame(width: 16)
                        .foregroundStyle(.theme(file.status == .deleted ? .danger : (file.status == .added ? .accentText : .warning)))
                    Text(file.path).lineLimit(1).truncationMode(.head)
                    if let original = file.originalPath {
                        Text("← \(original)").font(.caption).foregroundStyle(.theme(.textSubtle)).lineLimit(1)
                    }
                }
                .tag(file.path)
                .contextMenu {
                    Button("File History") { showHistory(of: file.path) }
                    Button("Copy Path") { Clipboard.copy(file.path) }
                }
                .accessibilityIdentifier("commit-file-\(file.path)")
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.files.isEmpty && model.detailError == nil {
                Text("No file changes").foregroundStyle(.theme(.textSubtle))
            }
        }
    }

    private func showHistory(of path: String) {
        repository.section = .history
        repository.history.filter = GitLogFilter(path: path, followRenames: true)
        Task { await repository.history.reload() }
    }

    /// The diff of the selected file with who last changed each line to its left.
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if model.selectedFile != nil, model.selectedCommit != nil || model.comparison != nil {
                HStack {
                    Text(model.selectedFile ?? "").font(.callout).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Toggle("Blame", isOn: $showsBlame)
                        .toggleStyle(.checkbox)
                        .help("Show who last changed each line, to the left of the diff")
                        .accessibilityIdentifier("blame-toggle")
                        .disabled(model.blame == nil)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                Divider()
            }
            if let diff = model.diff {
                if let commit = model.selectedCommit, model.comparison == nil, diff.isDisplayable, !diff.index.isBinary {
                    CommitLineBar(repository: repository, app: app, diff: diff, commit: commit, selection: $lineSelection,
                                  canRewrite: canRewrite)
                    Divider()
                    DiffContentView(diff: diff, lineSelection: $lineSelection, blame: model.blameByLine, showsBlame: showsBlame)
                } else {
                    DiffContentView(diff: diff, blame: model.blameByLine, showsBlame: showsBlame)
                }
            } else if let error = model.detailError {
                ContentUnavailableView("Cannot show this", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.selectedFile == nil {
                ContentUnavailableView("No diff to show", systemImage: "plus.forwardslash.minus",
                                       description: Text("The diff, with blame beside it, appears here once a commit and a file are selected."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#if DEBUG
#Preview("History sidebar") {
    PreviewRepository(width: 340, height: 600) { repository, app in
        HistorySidebar(repository: repository, app: app)
    }
}
#endif

#if DEBUG
#Preview("Commit list") {
    PreviewRepository(width: 500, height: 600) { repository, app in
        CommitListView(repository: repository, app: app, model: repository.history)
    }
}
#endif

#if DEBUG
#Preview("History detail") {
    PreviewRepository(width: 800, height: 600) { repository, app in
        HistoryDetailView(repository: repository, app: app, model: repository.history)
    }
}
#endif
