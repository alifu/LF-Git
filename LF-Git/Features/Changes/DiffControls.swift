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

/// Buttons that act on the lines selected in the diff: stage or unstage them, or throw them away.
struct LineSelectionBar: View {
    let repository: RepositoryModel
    let app: AppModel
    let diff: GitDiffFile
    @Binding var selection: Set<Int>
    let staged: Bool

    /// The selected lines that really are additions or removals.
    private var changedLines: Set<Int> {
        selection.filter { line in
            guard line > diff.index.fileHeaderLineCount else { return false }
            let first = diff.text(ofLine: line).first
            return first == "+" || first == "-"
        }
    }

    private var hunk: DiffHunk? {
        let hunks = Set(changedLines.compactMap { line in diff.index.hunks.first { line > $0.headerLine && line <= $0.lastLine }?.id })
        guard hunks.count == 1, let id = hunks.first else { return nil }
        return diff.index.hunks.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 10) {
            if changedLines.isEmpty {
                Text("Select lines in the diff to stage or discard them one by one.")
                    .font(.callout).foregroundStyle(.theme(.textSubtle))
            } else if let hunk {
                Text("\(changedLines.count) line\(changedLines.count == 1 ? "" : "s") selected").font(.callout)
                Button(staged ? "Unstage Lines" : "Stage Lines") {
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
