import AppKit
import LFKit
import SwiftUI

/// One changed file in a changes list: status letter, name, folder, a stage/unstage button and a context menu.
struct ChangeRow: View {
    let change: GitChange
    let staged: Bool
    /// A flat list shows where the file lives; inside a folder row that is redundant.
    let showsFolder: Bool
    let app: AppModel
    let repository: RepositoryModel
    @Binding var discarding: [GitChange]

    private var status: GitFileStatus { staged ? change.index : change.worktree }
    private var name: String { (change.path as NSString).lastPathComponent }
    private var folder: String { (change.path as NSString).deletingLastPathComponent }
    private var subtitle: String? {
        if let original = change.originalPath { return "from \(original)" }
        return showsFolder && !folder.isEmpty ? folder : nil
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(status.symbol)
                .font(.caption.monospaced().weight(.bold))
                .frame(width: 16)
                .foregroundStyle(.theme(color))
                .accessibilityLabel(label)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.theme(.textSubtle))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            Button {
                app.run {
                    if staged { try await repository.changes.unstage(change) } else { try await repository.changes.stage([change.path]) }
                }
            } label: {
                Image(systemName: staged ? "minus.circle" : "plus.circle")
            }
            .buttonStyle(.borderless)
            .help(staged ? "Unstage \(name) (Space)" : "Stage \(name) (Space)")
            .accessibilityIdentifier("\(staged ? "unstage" : "stage")-\(change.path)")
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button(staged ? "Unstage" : "Stage") {
                app.run { staged ? try await repository.changes.unstage(change) : try await repository.changes.stage([change.path]) }
            }
            if !staged {
                Button("Discard Changes…", role: .destructive) { discarding = [change] }
            }
            Divider()
            Menu("Ignore") {
                Button("Add to .gitignore") { ignore(.gitignore) }
                Button("Add to Local Exclude (.git/info/exclude)") { ignore(.localExclude) }
            }
            Menu("Stash This File") {
                Button("Stash…") { stash(includeUntracked: change.kind == .untracked) }
            }
            Button("File History") {
                repository.section = .history
                repository.history.filter = GitLogFilter(path: change.path, followRenames: true)
                Task { await repository.history.reload() }
            }
            Divider()
            Button("Open File") { NSWorkspace.shared.open(repository.root.appendingPathComponent(change.path)) }
                .disabled(change.worktree == .deleted)
            Button("Copy Path") { Clipboard.copy(change.path) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([repository.root.appendingPathComponent(change.path)])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("change-\(staged ? "staged" : "unstaged")-\(change.path)")
    }

    private func ignore(_ scope: IgnoreScope) {
        let path = change.path
        app.run { try await repository.perform("Ignoring…") { client, _ in try client.ignore([path], scope: scope) } }
    }

    private func stash(includeUntracked: Bool) {
        let path = change.path
        repository.ask(PendingPrompt(title: "Stash \(name)", message: "A name helps you find it later (optional).",
                                     placeholder: "Message", confirmTitle: "Stash") { message in
            app.run {
                try await repository.perform("Stashing…") { client, _ in
                    try client.stashPush(message: message, includeUntracked: includeUntracked, paths: [path])
                }
            }
        })
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
