import AppKit
import LFKit
import SwiftUI

/// Staged and unstaged files as collapsible sections of folders, with the commit box underneath.
/// Space stages or unstages the selected files.
struct ChangesSidebar: View {
    let repository: RepositoryModel
    let app: AppModel
    @State private var discarding: [GitChange] = []
    @State private var picked: Set<ChangeSelection> = []
    /// Sections and folders the user closed; everything is open by default.
    @State private var collapsed: Set<String> = []
    @AppStorage("changes.showsTree") private var showsTree = true

    private var changes: ChangesModel { repository.changes }
    private var staged: [GitChange] { repository.status.staged }
    private var unstaged: [GitChange] { repository.status.unstaged }

    var body: some View {
        VStack(spacing: 0) {
            ListActionBar {
                Button { showsTree.toggle() } label: {
                    Label(showsTree ? "Show as List" : "Show as Tree", systemImage: showsTree ? "list.bullet" : "folder")
                }
                .help(showsTree ? "Show every file in one flat list" : "Group the files by folder")
                .accessibilityIdentifier("changes-tree-toggle")
                Button { collapsed = [] } label: { Label("Expand All", systemImage: "chevron.down.2") }
                    .help("Open every section and folder")
                    .accessibilityIdentifier("changes-expand-all")
                Button { collapsed = Set(allKeys) } label: { Label("Collapse All", systemImage: "chevron.up.2") }
                    .help("Close every section and folder")
                    .accessibilityIdentifier("changes-collapse-all")
            }
            .labelStyle(.iconOnly)
            // `set: { pick($0) }`, not `set: pick`: the method reference crashes the Swift 6.2 compiler (IRGen).
            List(selection: Binding(get: { picked }, set: { pick($0) })) {
                if repository.status.isClean {
                    ContentUnavailableView("No changes", systemImage: "checkmark.circle",
                                           description: Text("The working tree matches the last commit."))
                        .listRowSeparator(.hidden)
                }
                if !staged.isEmpty {
                    section("Staged", key: "section:staged", changes: staged, isStaged: true, action: "Unstage All") {
                        app.run { try await changes.unstageAll() }
                    }
                }
                if !unstaged.isEmpty {
                    section("Changes", key: "section:unstaged", changes: unstaged, isStaged: false, action: "Stage All") {
                        app.run { try await changes.stageAll() }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("changes-list")
            .onKeyPress(.space) { toggleStage() }
            .onChange(of: changes.selection) { syncPicked() }
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
                app.run { try await changes.discard(targets) }
            }
        } message: {
            Text("This cannot be undone. Untracked files are deleted.")
        }
    }

    // MARK: - Sections

    private func section(_ title: String, key: String, changes list: [GitChange], isStaged: Bool, action: String,
                         perform: @escaping () -> Void) -> some View {
        Section(isExpanded: expansion(key)) {
            if showsTree {
                ChangeTreeRows(nodes: PathNode.build(list, path: \.path), isStaged: isStaged, repository: repository, app: app,
                               discarding: $discarding, collapsed: $collapsed)
            } else {
                ForEach(list) { change in
                    ChangeRow(change: change, staged: isStaged, showsFolder: true, app: app, repository: repository, discarding: $discarding)
                        .tag(ChangeSelection(path: change.path, staged: isStaged))
                        .id(ChangeSelection(path: change.path, staged: isStaged))
                }
            }
        } header: {
            HStack {
                Text("\(title) · \(list.count)")
                Spacer()
                Button(action, action: perform)
                    .buttonStyle(.link)
                    .font(.caption)
                    .accessibilityIdentifier(action.lowercased().replacingOccurrences(of: " ", with: "-"))
            }
        }
    }

    private func expansion(_ key: String) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(key) }, set: { open in
            if open { collapsed.remove(key) } else { collapsed.insert(key) }
        })
    }

    /// Every section and folder, for "Collapse All".
    private var allKeys: [String] {
        func folders(_ nodes: [PathNode<GitChange>], prefix: String) -> [String] {
            nodes.filter(\.isFolder).flatMap { [prefix + $0.id] + folders($0.children ?? [], prefix: prefix) }
        }
        return ["section:staged", "section:unstaged"]
            + (showsTree ? folders(PathNode.build(staged, path: \.path), prefix: "staged:")
                + folders(PathNode.build(unstaged, path: \.path), prefix: "unstaged:") : [])
    }

    // MARK: - Selection and the space key

    /// One selected file shows its diff; several are kept for staging them together.
    private func pick(_ selection: Set<ChangeSelection>) {
        picked = selection
        if selection.count == 1 {
            Task { await changes.select(selection.first) }
        } else if selection.isEmpty {
            Task { await changes.select(nil) }
        }
    }

    /// The model moves the selection when a staged file changes lists; follow it.
    private func syncPicked() {
        guard let selection = changes.selection else { return }
        if !picked.contains(selection) { picked = [selection] }
    }

    /// Stages the selected unstaged files and unstages the selected staged ones.
    private func toggleStage() -> KeyPress.Result {
        let targets = picked.compactMap { selection in changes.change(for: selection).map { (selection, $0) } }
        guard !targets.isEmpty else { return .ignored }
        let toStage = targets.filter { !$0.0.staged }.map(\.1.path)
        let toUnstage = targets.filter(\.0.staged).flatMap { [$0.1.path] + ($0.1.originalPath.map { [$0] } ?? []) }
        let moved = Set(targets.map { ChangeSelection(path: $0.0.path, staged: !$0.0.staged) })
        app.run {
            if !toStage.isEmpty { try await changes.stage(toStage) }
            if !toUnstage.isEmpty { try await changes.unstage(toUnstage) }
            picked = moved
        }
        return .handled
    }
}

/// Folders (open or closed) and the files inside them, one level at a time.
private struct ChangeTreeRows: View {
    let nodes: [PathNode<GitChange>]
    let isStaged: Bool
    let repository: RepositoryModel
    let app: AppModel
    @Binding var discarding: [GitChange]
    @Binding var collapsed: Set<String>

    var body: some View {
        ForEach(nodes) { node in
            if let change = node.item {
                ChangeRow(change: change, staged: isStaged, showsFolder: false, app: app, repository: repository, discarding: $discarding)
                    .tag(ChangeSelection(path: change.path, staged: isStaged))
                    // The same path is a row in both sections; its identity must say which, or a row that moved
                    // between them can be left behind (stale highlight and button).
                    .id(ChangeSelection(path: change.path, staged: isStaged))
            } else {
                DisclosureGroup(isExpanded: expansion(node)) {
                    ChangeTreeRows(nodes: node.children ?? [], isStaged: isStaged, repository: repository, app: app,
                                   discarding: $discarding, collapsed: $collapsed)
                } label: {
                    folderLabel(node)
                }
            }
        }
    }

    private func key(_ node: PathNode<GitChange>) -> String { (isStaged ? "staged:" : "unstaged:") + node.id }

    private func expansion(_ node: PathNode<GitChange>) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(key(node)) }, set: { open in
            if open { collapsed.remove(key(node)) } else { collapsed.insert(key(node)) }
        })
    }

    private func folderLabel(_ node: PathNode<GitChange>) -> some View {
        let files = node.items
        return HStack(spacing: 6) {
            Image(systemName: "folder").foregroundStyle(.theme(.textSubtle))
            Text(node.name).lineLimit(1).truncationMode(.middle)
            Text("\(files.count)").font(.caption.monospacedDigit()).foregroundStyle(.theme(.textSubtle))
            Spacer(minLength: 4)
            Button {
                app.run {
                    if isStaged {
                        try await repository.changes.unstage(files.flatMap { [$0.path] + ($0.originalPath.map { [$0] } ?? []) })
                    } else {
                        try await repository.changes.stage(files.map(\.path))
                    }
                }
            } label: {
                Image(systemName: isStaged ? "minus.circle" : "plus.circle")
            }
            .buttonStyle(.borderless)
            .help(isStaged ? "Unstage every file in \(node.name)" : "Stage every file in \(node.name)")
            .accessibilityIdentifier("\(isStaged ? "unstage" : "stage")-folder-\(node.id)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folder-\(isStaged ? "staged" : "unstaged")-\(node.id)")
    }
}

private struct ChangeRow: View {
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

#if DEBUG
#Preview("Changes sidebar") {
    PreviewRepository(width: 340, height: 600) { repository, app in
        ChangesSidebar(repository: repository, app: app)
    }
}
#endif
