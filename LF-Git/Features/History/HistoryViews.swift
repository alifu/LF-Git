import LFKit
import SwiftUI

/// The commit list with the graph.
struct HistorySidebar: View {
    let repository: RepositoryModel

    private var history: HistoryModel { repository.history }
    static let rowHeight: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            List(selection: Binding(get: { history.selection }, set: { id in Task { await history.select(id) } })) {
                ForEach(Array(history.commits.enumerated()), id: \.element.id) { index, commit in
                    CommitRow(commit: commit, row: history.graph.rows.indices.contains(index) ? history.graph.rows[index] : nil,
                              currentBranch: repository.status.branch)
                        .tag(commit.id)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .onAppear {
                            if index >= history.commits.count - 20 {
                                Task { await history.loadMore() }
                            }
                        }
                }
                if history.isLoading {
                    ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            .accessibilityIdentifier("history-list")
            .overlay {
                if history.hasLoaded && history.commits.isEmpty {
                    ContentUnavailableView("No commits yet", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .task {
            if !history.hasLoaded { await history.reload() }
        }
    }
}

private struct CommitRow: View {
    let commit: GitCommit
    let row: CommitGraph.Row?
    let currentBranch: String?

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
                }
                Text("\(commit.authorName) · \(commit.date.formatted(.relative(presentation: .named))) · \(commit.shortHash)")
                    .font(.caption)
                    .foregroundStyle(.theme(.textSubtle))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: HistorySidebar.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("commit-\(commit.subject)")
    }
}

/// The selected commit: who and when, its files, and the diff of one file.
struct HistoryDetailView: View {
    let repository: RepositoryModel

    private var history: HistoryModel { repository.history }

    var body: some View {
        Group {
            if let commit = history.selectedCommit {
                VStack(spacing: 0) {
                    header(commit)
                    Divider()
                    VSplitView {
                        fileList
                            .frame(minHeight: 90, idealHeight: 130)
                        diff
                            .frame(minHeight: 160)
                    }
                }
            } else {
                ContentUnavailableView("Select a commit", systemImage: "clock.arrow.circlepath")
            }
        }
        .background(.theme(.background))
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
        List(selection: Binding(get: { history.selectedFile }, set: { path in Task { await history.selectFile(path) } })) {
            ForEach(history.files) { file in
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
                .accessibilityIdentifier("commit-file-\(file.path)")
            }
        }
        .listStyle(.plain)
        .overlay {
            if history.files.isEmpty && history.detailError == nil {
                Text("No file changes").foregroundStyle(.theme(.textSubtle))
            }
        }
    }

    @ViewBuilder
    private var diff: some View {
        if let diff = history.diff {
            DiffContentView(diff: diff)
        } else if let error = history.detailError {
            ContentUnavailableView("Cannot show this", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            Color.clear
        }
    }
}
