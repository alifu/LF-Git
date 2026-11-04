import AppKit
import LFKit
import SwiftUI

/// The commit message, amend and commit. Docked (in a list or a lane) or in a floating panel; while it floats,
/// the docked one shows a notice instead, so there is only ever one editor and one ⌘↩. Body: O(1).
struct CommitBox: View {
    let repository: RepositoryModel
    let app: AppModel
    /// This box is the one inside the floating panel.
    var isFloating = false
    @FocusState private var focused: Bool
    @Environment(\.changesFloating) private var floating

    private static let dockedEditorHeight: CGFloat = 72
    private static let floatingEditorHeight: CGFloat = 150

    private var changes: ChangesModel { repository.changes }

    var body: some View {
        if !isFloating && floating.wrappedValue.showsEditor {
            PoppedOutNotice(title: "The commit message is in a floating panel", symbol: "macwindow.on.rectangle",
                            identifier: "dock-commit-editor") {
                floating.wrappedValue = floating.wrappedValue.with(editor: false)
            }
        } else {
            editor
        }
    }

    @ViewBuilder
    private var editor: some View {
        @Bindable var changes = changes
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $changes.commitMessage)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(height: isFloating ? Self.floatingEditorHeight : Self.dockedEditorHeight)
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
            // One row when the column is wide enough; in a narrow one (the sidebar's 280pt minimum) the checkboxes
            // go above the button instead of being squeezed and truncated.
            ViewThatFits(in: .horizontal) {
                HStack {
                    options
                    Spacer()
                    commitButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack { options }
                    HStack {
                        Spacer()
                        commitButton
                    }
                }
            }
            HStack(spacing: 6) {
                branchLine
                Spacer(minLength: 4)
                if !isFloating { popOutButton }
            }
        }
        .padding(10)
        .background(.theme(.surfaceRaised))
    }

    @ViewBuilder
    private var branchLine: some View {
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

    private var popOutButton: some View {
        Button { floating.wrappedValue = floating.wrappedValue.with(editor: true) } label: {
            Image(systemName: "macwindow.on.rectangle")
        }
        .buttonStyle(.borderless)
        .help("Edit the commit message in a floating panel")
        .accessibilityLabel("Pop Out Commit Editor")
        .accessibilityIdentifier("pop-out-commit-editor")
    }

    @ViewBuilder
    private var options: some View {
        @Bindable var changes = changes
        Toggle("Amend last commit", isOn: Binding(
            get: { changes.amend },
            set: { on in Task { await changes.setAmend(on) } }
        ))
        .toggleStyle(.checkbox)
        .font(.callout)
        .accessibilityIdentifier("amend")
        Toggle("Skip hooks", isOn: $changes.noVerify)
            .toggleStyle(.checkbox)
            .font(.callout)
            .help("Commit with --no-verify: pre-commit and commit-msg hooks do not run")
            .accessibilityIdentifier("no-verify")
    }

    private var commitButton: some View {
        Button(changes.amend ? "Amend" : "Commit") {
            Task {
                do { try await changes.commit() } catch { app.report(error) }
            }
        }
        .buttonStyle(.prominentPill)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!changes.canCommit)
        .accessibilityIdentifier("commit-button")
    }
}

/// The diff of the selected change. Body: O(1) here; the diff table draws O(visible rows).
struct ChangesDetailView: View {
    let repository: RepositoryModel
    let app: AppModel
    /// Adds a ✕ to the header, for a diff shown as a panel.
    var onClose: (() -> Void)?
    /// False inside the floating diff panel itself.
    var allowsPopOut = true
    @State private var lineSelection: Set<Int> = []
    @Environment(\.changesFloating) private var floating

    private var changes: ChangesModel { repository.changes }

    var body: some View {
        Group {
            if allowsPopOut && floating.wrappedValue.showsDiff {
                EmptyPane("The diff is in a floating panel", symbol: "macwindow.on.rectangle",
                          message: "Close the panel, or bring the diff back here.") {
                    Button("Bring Back") { floating.wrappedValue = floating.wrappedValue.with(diff: false) }
                        .accessibilityIdentifier("dock-diff")
                }
                .background(DotGridBackground())
            } else if let selection = changes.selection, let change = changes.change(for: selection) {
                VStack(spacing: 0) {
                    header(selection: selection, change: change)
                    Divider()
                    if canPickLines(selection: selection, change: change), let diff = changes.diff {
                        LineSelectionBar(repository: repository, app: app, diff: diff, selection: $lineSelection, staged: selection.staged)
                        Divider()
                    }
                    content(selection: selection, change: change)
                }
            } else {
                EmptyPane("Select a change", symbol: "plus.forwardslash.minus",
                          message: "Choose a file to see what changed, and stage it or single hunks.")
                    .background(DotGridBackground())
            }
        }
        .background(.theme(.background))
    }

    /// One row when it fits; in a narrow panel the actions go on a second row.
    private func header(selection: ChangeSelection, change: GitChange) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                fileTitle(change)
                Spacer()
                headerActions(selection: selection, change: change)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    fileTitle(change)
                    Spacer(minLength: 4)
                    if let onClose { CloseButton(label: "Close Diff", action: onClose) }
                }
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    headerActions(selection: selection, change: change, showsClose: false)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.theme(.surfaceRaised))
    }

    private func fileTitle(_ change: GitChange) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text((change.path as NSString).lastPathComponent).font(.headline).foregroundStyle(.theme(.text))
            Text(change.path).font(.caption).foregroundStyle(.theme(.textSubtle)).lineLimit(1).truncationMode(.head)
        }
    }

    @ViewBuilder
    private func headerActions(selection: ChangeSelection, change: GitChange, showsClose: Bool = true) -> some View {
        DiffOptionsMenu(changes: changes)
        Text(selection.staged ? "Staged" : "Not staged")
            .font(.callout)
            .foregroundStyle(.theme(selection.staged ? .accentText : .textSubtle))
            .fixedSize()
        Button(selection.staged ? "Unstage File" : "Stage File") {
            Task {
                do {
                    if selection.staged { try await changes.unstage(change) } else { try await changes.stage([change.path]) }
                } catch { app.report(error) }
            }
        }
        if allowsPopOut {
            Button { floating.wrappedValue = floating.wrappedValue.with(diff: true) } label: {
                Image(systemName: "macwindow.on.rectangle")
            }
            .buttonStyle(.borderless)
            .help("Pop out the diff into a floating panel with the file list")
            .accessibilityLabel("Pop Out Diff")
            .accessibilityIdentifier("pop-out-diff")
        }
        if showsClose, let onClose { CloseButton(label: "Close Diff", action: onClose) }
    }

    @ViewBuilder
    private func content(selection: ChangeSelection, change: GitChange) -> some View {
        if let diff = changes.diff {
            DiffContentView(diff: diff, hunkAction: hunkAction(selection: selection, change: change),
                            lineSelection: canPickLines(selection: selection, change: change) ? $lineSelection : nil,
                            onSpace: { stageSelectedLines(selection: selection, change: change, diff: diff) })
        } else if let error = changes.diffError {
            ContentUnavailableView("Cannot show the diff", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Space in the diff: stage (or unstage) the selected lines, or the whole file when no line is selected.
    private func stageSelectedLines(selection: ChangeSelection, change: GitChange, diff: GitDiffFile) {
        let lines = diff.changedLines(in: lineSelection)
        guard !lines.isEmpty, canPickLines(selection: selection, change: change), let hunk = diff.singleHunk(containing: lines) else {
            app.run {
                if selection.staged { try await changes.unstage(change) } else { try await changes.stage([change.path]) }
            }
            return
        }
        app.run {
            try await changes.applyLines(lines, in: hunk, of: diff)
            lineSelection = []
        }
    }

    private func canPickLines(selection: ChangeSelection, change: GitChange) -> Bool {
        guard changes.diffSelection == selection, changes.diff?.isStageable == true else { return false }
        // A new file can be staged line by line too (git registers it as "intent to add" first).
        if change.kind == .untracked { return !selection.staged }
        return change.kind == .ordinary && [.modified, .added].contains(selection.staged ? change.index : change.worktree)
    }

    /// Single hunks can be staged for ordinary modifications; new, deleted and renamed files go as a whole.
    private func hunkAction(selection: ChangeSelection, change: GitChange) -> HunkAction? {
        // Only while the diff on screen belongs to the selected row, and no git command is running.
        guard changes.diffSelection == selection, !repository.isBusy, change.kind == .ordinary, changes.diff?.isStageable == true,
              (selection.staged ? change.index : change.worktree) == .modified else { return nil }
        return HunkAction(title: selection.staged ? "Unstage Hunk" : "Stage Hunk") { diff, hunk in
            Task {
                do { try await changes.applyHunk(hunk, of: diff) } catch { app.report(error) }
            }
        }
    }
}

/// A diff, or the reason there is nothing to draw.
struct DiffContentView: View {
    let diff: GitDiffFile
    var hunkAction: HunkAction?
    var lineSelection: Binding<Set<Int>>?
    /// Who last changed each line (new-side line numbers); shown to the left of the diff while `showsBlame` is on.
    var blame: [Int: GitBlameLine] = [:]
    var showsBlame = true
    var onSpace: (() -> Void)?

    var body: some View {
        if diff.index.isBinary {
            ContentUnavailableView("Binary file", systemImage: "doc.zipper", description: Text("A binary file has no line diff."))
        } else if !diff.isDisplayable {
            ContentUnavailableView("Cannot show this diff", systemImage: "doc.questionmark",
                                   description: Text("The file is not UTF-8 text (for example UTF-16)."))
        } else if diff.lineCount == 0 {
            ContentUnavailableView("No differences", systemImage: "equal.circle")
        } else {
            DiffTableView(diff: diff, hunkAction: hunkAction, selection: lineSelection, blame: blame, showsBlame: showsBlame,
                          onSpace: onSpace)
        }
    }
}

#if DEBUG
#Preview("Commit box") {
    PreviewRepository(width: 340) { repository, app in
        CommitBox(repository: repository, app: app)
    }
}
#endif

#if DEBUG
#Preview("Changes detail") {
    PreviewRepository(width: 800, height: 600) { repository, app in
        ChangesDetailView(repository: repository, app: app)
    }
}
#endif
