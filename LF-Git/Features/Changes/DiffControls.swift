import LFKit
import SwiftUI

/// Whitespace, context size and rename detection of the diff on screen.
struct DiffOptionsMenu: View {
    let changes: ChangesModel

    var body: some View {
        Menu {
            Toggle("Ignore Whitespace", isOn: Binding(
                get: { changes.options.ignoreWhitespace },
                set: { on in update { $0.ignoreWhitespace = on } }
            ))
            Toggle("Detect Renames", isOn: Binding(
                get: { changes.options.detectRenames },
                set: { on in update { $0.detectRenames = on } }
            ))
            Divider()
            Button("More Context") { update { $0.contextLines = min((($0.contextLines ?? 3) + 2), 1000) } }
            Button("Less Context") { update { $0.contextLines = max((($0.contextLines ?? 3) - 2), 0) } }
            Button("Default Context (3 lines)") { update { $0.contextLines = nil } }
        } label: {
            Label("Diff Options", systemImage: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Whitespace, context lines, renames")
        .accessibilityIdentifier("diff-options")
    }

    private func update(_ change: (inout DiffOptions) -> Void) {
        var next = changes.options
        change(&next)
        Task { await changes.setOptions(DiffOptions(ignoreWhitespace: next.ignoreWhitespace, contextLines: next.contextLines,
                                                    detectRenames: next.detectRenames)) }
    }
}

extension GitDiffFile {
    /// The selected diff lines that really are additions or removals.
    func changedLines(in selection: Set<Int>) -> Set<Int> {
        selection.filter { line in
            guard line > index.fileHeaderLineCount else { return false }
            let first = text(ofLine: line).first
            return first == "+" || first == "-"
        }
    }

    /// The hunk all of `lines` belong to, or nil when they span several hunks.
    func singleHunk(containing lines: Set<Int>) -> DiffHunk? {
        let hunks = Set(lines.compactMap { line in index.hunks.first { line > $0.headerLine && line <= $0.lastLine }?.id })
        guard hunks.count == 1, let id = hunks.first else { return nil }
        return index.hunks.first { $0.id == id }
    }
}

/// Buttons that act on the lines selected in the diff: stage or unstage them, or throw them away.
struct LineSelectionBar: View {
    let repository: RepositoryModel
    let app: AppModel
    let diff: GitDiffFile
    @Binding var selection: Set<Int>
    let staged: Bool

    /// The selected lines that really are additions or removals.
    private var changedLines: Set<Int> { diff.changedLines(in: selection) }
    private var hunk: DiffHunk? { diff.singleHunk(containing: changedLines) }

    var body: some View {
        HStack(spacing: 10) {
            if changedLines.isEmpty {
                Text("Click lines in the diff (⇧ or ⌘ for several), then press Space to stage them.")
                    .font(.callout).foregroundStyle(.theme(.textSubtle))
            } else if let hunk {
                Text("\(changedLines.count) line\(changedLines.count == 1 ? "" : "s") selected").font(.callout)
                Button(staged ? "Unstage Lines (Space)" : "Stage Lines (Space)") {
                    app.run {
                        try await repository.changes.applyLines(changedLines, in: hunk, of: diff)
                        selection = []
                    }
                }
                .accessibilityIdentifier("stage-lines")
                if !staged {
                    Button("Discard Lines…", role: .destructive) {
                        let lines = changedLines
                        repository.confirm(PendingConfirmation(
                            title: "Discard \(lines.count) selected line\(lines.count == 1 ? "" : "s")?",
                            message: "They are removed from the file on disk. This cannot be undone.", confirmTitle: "Discard Lines"
                        ) {
                            app.run {
                                try await repository.changes.discardLines(lines, in: hunk, of: diff)
                                selection = []
                            }
                        })
                    }
                    .accessibilityIdentifier("discard-lines")
                }
                Button("Clear") { selection = [] }
            } else {
                Text("Pick lines inside a single hunk.").font(.callout).foregroundStyle(.theme(.warning))
            }
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.theme(.surfaceRaised))
        .disabled(repository.isBusy)
    }
}

/// Buttons that reuse selected lines of a commit: apply them again, take them back, or cut them out of the commit.
struct CommitLineBar: View {
    let repository: RepositoryModel
    let app: AppModel
    let diff: GitDiffFile
    let commit: GitCommit
    @Binding var selection: Set<Int>
    /// Rewriting is only possible on the checked-out branch.
    let canRewrite: Bool

    private var changedLines: Set<Int> { diff.changedLines(in: selection) }
    private var hunk: DiffHunk? { diff.singleHunk(containing: changedLines) }

    var body: some View {
        HStack(spacing: 10) {
            if let hunk, !changedLines.isEmpty {
                Text("\(changedLines.count) line\(changedLines.count == 1 ? "" : "s")").font(.callout)
                Menu("Use Lines") {
                    Button("Apply to Working Tree") { apply(hunk, to: .workingTree, reverse: false) }
                    Button("Apply to Index") { apply(hunk, to: .index, reverse: false) }
                    Divider()
                    Button("Revert in Working Tree") { apply(hunk, to: .workingTree, reverse: true) }
                    Button("Revert in Index and Working Tree") { apply(hunk, to: .both, reverse: true) }
                    if canRewrite {
                        Divider()
                        Button("Remove from This Commit…", role: .destructive) { remove(hunk) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("use-lines")
                Button("Clear") { selection = [] }
            } else {
                Text(changedLines.isEmpty ? "Select lines to reuse them." : "Pick lines inside a single hunk.")
                    .font(.callout).foregroundStyle(.theme(.textSubtle))
            }
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.theme(.surfaceRaised))
        .disabled(repository.isBusy)
    }

    private func apply(_ hunk: DiffHunk, to target: PatchTarget, reverse: Bool) {
        let lines = changedLines
        app.run {
            try await repository.perform(reverse ? "Reverting lines…" : "Applying lines…") { client, _ in
                try client.applyCommitLines(lines, in: hunk, of: diff, to: target, reverse: reverse)
            }
            selection = []
        }
    }

    private func remove(_ hunk: DiffHunk) {
        let lines = changedLines
        let commit = commit
        repository.confirm(PendingConfirmation(
            title: "Remove \(lines.count) line\(lines.count == 1 ? "" : "s") from “\(commit.subject)”?",
            message: "The history after this commit is rewritten. Your work tree must be clean.", confirmTitle: "Remove from Commit"
        ) {
            app.run {
                try await repository.perform("Rewriting history…") { client, _ in
                    try client.removeLines(lines, in: hunk, of: diff, from: commit)
                }
                selection = []
            }
        })
    }
}
