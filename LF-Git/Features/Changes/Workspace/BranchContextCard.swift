import LFKit
import SwiftUI

/// The checked-out branch beside the commit box: its name and upstream, ahead/behind, Push and Pull (the existing
/// toolbar actions), an optional "your commit goes here" marker and the latest commits of the History log.
/// Body: O(`commitLimit`) rows.
struct BranchContextCard: View {
    let repository: RepositoryModel
    let app: AppModel
    /// The Lanes layout marks where the next commit lands.
    var showsUpcomingCommit = false
    /// Commits are read-only without it; with it a click opens a preview.
    var onSelectCommit: ((GitCommit) -> Void)?
    var selectedCommit: GitCommit.ID?

    static let commitLimit = 8

    private var status: GitStatus { repository.status }
    private var history: HistoryModel { repository.history }
    private var isIdle: Bool { !repository.isBusy && repository.operation == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            Divider()
            commitList
        }
        .lfCard()
        .task { if !history.hasLoaded { await history.reload() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace-branch")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(.theme(.textSubtle))
                Text(status.branch ?? "Detached HEAD")
                    .font(.headline).foregroundStyle(.theme(.text)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                aheadBehind
            }
            Text(status.upstream.map { "Tracks \($0)" } ?? "No upstream branch")
                .font(.caption).foregroundStyle(.theme(.textSubtle)).lineLimit(1)
            HStack(spacing: 8) {
                Button { app.run { try await repository.pull() } } label: { Label("Pull", systemImage: "arrow.down") }
                    .disabled(!isIdle || status.upstream == nil)
                    .help("Pull (fast-forward only)")
                    .accessibilityIdentifier("workspace-pull")
                Button { app.run { try await repository.push() } } label: { Label("Push", systemImage: "arrow.up") }
                    .disabled(!isIdle || status.branch == nil)
                    .help(status.upstream == nil ? "Publish this branch" : "Push")
                    .accessibilityIdentifier("workspace-push")
            }
            .buttonStyle(.pill)
        }
        .padding(12)
        .background(.theme(.surfaceRaised))
    }

    private var aheadBehind: some View {
        HStack(spacing: 6) {
            Label("\(status.ahead)", systemImage: "arrow.up")
            Label("\(status.behind)", systemImage: "arrow.down")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.theme(.textSubtle))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.ahead) ahead, \(status.behind) behind")
    }

    private var commitList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if showsUpcomingCommit { UpcomingCommitRow() }
                ForEach(history.commits.prefix(Self.commitLimit)) { commit in
                    LaneCommitRow(commit: commit, isSelected: commit.id == selectedCommit, onSelect: onSelectCommit)
                }
                if history.commits.isEmpty {
                    Text(history.isLoading ? "Loading commits…" : "No commits yet")
                        .font(.callout).foregroundStyle(.theme(.textSubtle)).padding(12)
                }
                if !history.filter.isEmpty {
                    Text("Filtered as in History").font(.caption).foregroundStyle(.theme(.textSubtle)).padding(12)
                }
            }
        }
    }
}

/// "Your commit goes here", above the newest commit (Figma "Committing"). O(1).
private struct UpcomingCommitRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle().strokeBorder(.theme(.accent), lineWidth: 2).frame(width: 10, height: 10)
            Text("Your commit goes here")
                .font(.caption.weight(.medium))
                .foregroundStyle(.theme(.onAccent))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.theme(.accent)))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .accessibilityIdentifier("upcoming-commit")
    }
}

/// One commit of the lane: a dot on the line, the subject and the short hash. O(1).
private struct LaneCommitRow: View {
    let commit: GitCommit
    let isSelected: Bool
    let onSelect: ((GitCommit) -> Void)?

    var body: some View {
        Group {
            if let onSelect {
                Button { onSelect(commit) } label: { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
        .accessibilityIdentifier("lane-commit-\(commit.shortHash)")
    }

    private var row: some View {
        HStack(spacing: 10) {
            Circle().fill(.theme(.textSubtle)).frame(width: 8, height: 8).padding(.leading, 1)
            Text(commit.subject).lineLimit(1).foregroundStyle(.theme(.text))
            Spacer(minLength: 4)
            Text(commit.shortHash).font(.caption.monospaced()).foregroundStyle(.theme(.textSubtle))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.theme(.accentSubtle) : Color.clear)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(.theme(.border)).frame(height: 1) }
    }
}
