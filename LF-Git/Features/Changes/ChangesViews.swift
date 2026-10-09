import LFKit
import SwiftUI

/// Staged and unstaged files, with the commit box underneath.
struct ChangesSidebar: View {
    let repository: RepositoryModel
    let app: AppModel
    @State private var discarding: [GitChange] = []

    private var changes: ChangesModel { repository.changes }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { changes.selection }, set: { selection in Task { await changes.select(selection) } })) {
                if repository.status.isClean {
                    ContentUnavailableView("No changes", systemImage: "checkmark.circle",
                                           description: Text("The working tree matches the last commit."))
                        .listRowSeparator(.hidden)
                }
                if !repository.status.staged.isEmpty {
                    Section {
                        ForEach(repository.status.staged) { change in
                            ChangeRow(change: change, staged: true, app: app, repository: repository, discarding: $discarding)
                                .tag(ChangeSelection(path: change.path, staged: true))
                        }
                    } header: {
                        sectionHeader("Staged", count: repository.status.staged.count, action: "Unstage All") {
                            run { try await changes.unstageAll() }
                        }
                    }
                }
                if !repository.status.unstaged.isEmpty {
                    Section {
                        ForEach(repository.status.unstaged) { change in
                            ChangeRow(change: change, staged: false, app: app, repository: repository, discarding: $discarding)
                                .tag(ChangeSelection(path: change.path, staged: false))
                        }
                    } header: {
                        sectionHeader("Changes", count: repository.status.unstaged.count, action: "Stage All") {
                            run { try await changes.stageAll() }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("changes-list")
            Divider()
            CommitBox(repository: repository, app: app)
        }
        .confirmationDialog(
            discarding.count == 1 ? "Discard changes to \(discarding[0].path)?" : "Discard \(discarding.count) changes?",
            isPresented: Binding(get: { !discarding.isEmpty }, set: { if !$0 { discarding = [] } }),
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                let targets = discarding
                run { try await changes.discard(targets) }
            }
        } message: {
            Text("This cannot be undone. Untracked files are deleted.")
        }
    }

    private func sectionHeader(_ title: String, count: Int, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text("\(title) · \(count)")
            Spacer()
            Button(action, action: perform)
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityIdentifier(action.lowercased().replacingOccurrences(of: " ", with: "-"))
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { app.errorMessage = "\(error)" }
        }
    }
}

private struct ChangeRow: View {
    let change: GitChange
    let staged: Bool
    let app: AppModel
    let repository: RepositoryModel
    @Binding var discarding: [GitChange]

    private var status: GitFileStatus { staged ? change.index : change.worktree }
    private var name: String { (change.path as NSString).lastPathComponent }
    private var folder: String { (change.path as NSString).deletingLastPathComponent }

    var body: some View {
        HStack(spacing: 8) {
            Text(status.symbol)
                .font(.caption.monospaced().weight(.bold))
                .frame(width: 16)
                .foregroundStyle(.theme(color))
                .accessibilityLabel(label)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                if !folder.isEmpty || change.originalPath != nil {
                    Text(change.originalPath.map { "from \($0)" } ?? folder)
                        .font(.caption)
                        .foregroundStyle(.theme(.textSubtle))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            Button {
                Task {
                    do {
                        if staged { try await repository.changes.unstage(change) } else { try await repository.changes.stage([change.path]) }
                    } catch { app.errorMessage = "\(error)" }
                }
            } label: {
                Image(systemName: staged ? "minus.circle" : "plus.circle")
            }
            .buttonStyle(.borderless)
            .help(staged ? "Unstage \(name)" : "Stage \(name)")
            .accessibilityIdentifier("\(staged ? "unstage" : "stage")-\(change.path)")
        }
        .padding(.vertical, 1)
        .contextMenu {
            if !staged {
                Button("Discard Changes…", role: .destructive) { discarding = [change] }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("change-\(staged ? "staged" : "unstaged")-\(change.path)")
    }

    private var color: LFThemeToken {
        switch status {
        case .added, .untracked: .accentText
        case .deleted: .danger
        case .renamed, .copied: .info
        default: .warning
        }
    }

    private var label: String {
        switch status {
        case .added: "added"
        case .untracked: "untracked"
        case .deleted: "deleted"
        case .renamed: "renamed"
        case .copied: "copied"
        case .modified: "modified"
        default: "changed"
        }
    }
}

struct CommitBox: View {
    let repository: RepositoryModel
    let app: AppModel
    @FocusState private var focused: Bool

    private var changes: ChangesModel { repository.changes }

    var body: some View {
        @Bindable var changes = changes
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $changes.commitMessage)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(height: 72)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.theme(.surfaceRaised)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.theme(focused ? .accent : .border)))
                    .accessibilityIdentifier("commit-message")
                if changes.commitMessage.isEmpty {
                    Text(changes.amend ? "Amend message" : "Commit message")
                        .foregroundStyle(.theme(.textSubtle))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Toggle("Amend last commit", isOn: Binding(
                    get: { changes.amend },
                    set: { on in Task { await changes.setAmend(on) } }
                ))
                .toggleStyle(.checkbox)
                .font(.callout)
                .accessibilityIdentifier("amend")
                Spacer()
                Button(changes.amend ? "Amend" : "Commit") {
                    Task {
                        do { try await changes.commit() } catch { app.errorMessage = "\(error)" }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!changes.canCommit)
                .accessibilityIdentifier("commit-button")
            }
            if let branch = repository.status.branch {
                Text("on \(branch)")
                    .font(.caption)
                    .foregroundStyle(.theme(.textSubtle))
            } else if repository.status.isDetached {
                Label("Detached HEAD: commits belong to no branch", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.theme(.warning))
            }
        }
        .padding(10)
        .background(.theme(.surfaceRaised))
    }
}

/// The diff of the selected change.
struct ChangesDetailView: View {
    let repository: RepositoryModel
    let app: AppModel

    private var changes: ChangesModel { repository.changes }

    var body: some View {
        Group {
            if let selection = changes.selection, let change = changes.change(for: selection) {
                VStack(spacing: 0) {
                    header(selection: selection, change: change)
                    Divider()
                    content(selection: selection, change: change)
                }
            } else {
                ContentUnavailableView("Select a change", systemImage: "plus.forwardslash.minus",
                                       description: Text("Choose a file to see what changed, and stage it or single hunks."))
            }
        }
        .background(.theme(.background))
    }

    private func header(selection: ChangeSelection, change: GitChange) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text((change.path as NSString).lastPathComponent).font(.headline).foregroundStyle(.theme(.text))
                Text(change.path).font(.caption).foregroundStyle(.theme(.textSubtle)).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(selection.staged ? "Staged" : "Not staged")
                .font(.callout)
                .foregroundStyle(.theme(selection.staged ? .accentText : .textSubtle))
            Button(selection.staged ? "Unstage File" : "Stage File") {
                Task {
                    do {
                        if selection.staged { try await changes.unstage(change) } else { try await changes.stage([change.path]) }
                    } catch { app.errorMessage = "\(error)" }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.theme(.surfaceRaised))
    }

    @ViewBuilder
    private func content(selection: ChangeSelection, change: GitChange) -> some View {
        if let diff = changes.diff {
            DiffContentView(diff: diff, hunkAction: hunkAction(selection: selection, change: change))
        } else if let error = changes.diffError {
            ContentUnavailableView("Cannot show the diff", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Single hunks can be staged for ordinary modifications; new, deleted and renamed files go as a whole.
    private func hunkAction(selection: ChangeSelection, change: GitChange) -> HunkAction? {
        // Only while the diff on screen belongs to the selected row, and no git command is running.
        guard changes.diffSelection == selection, !repository.isBusy, change.kind == .ordinary,
              (selection.staged ? change.index : change.worktree) == .modified else { return nil }
        return HunkAction(title: selection.staged ? "Unstage Hunk" : "Stage Hunk") { diff, hunk in
            Task {
                do { try await changes.applyHunk(hunk, of: diff) } catch { app.errorMessage = "\(error)" }
            }
        }
    }
}

/// A diff, or the reason there is nothing to draw.
struct DiffContentView: View {
    let diff: GitDiffFile
    var hunkAction: HunkAction?

    var body: some View {
        if diff.index.isBinary {
            ContentUnavailableView("Binary file", systemImage: "doc.zipper", description: Text("A binary file has no line diff."))
        } else if !diff.isDisplayable {
            ContentUnavailableView("Cannot show this diff", systemImage: "doc.questionmark",
                                   description: Text("The file is not UTF-8 text (for example UTF-16)."))
        } else if diff.lineCount == 0 {
            ContentUnavailableView("No differences", systemImage: "equal.circle")
        } else {
            DiffTableView(diff: diff, hunkAction: hunkAction)
        }
    }
}
