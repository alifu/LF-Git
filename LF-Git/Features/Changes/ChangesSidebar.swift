import AppKit
import LFKit
import SwiftUI

/// Which sections a changes list shows. Fixed for the life of a list, so a section is never inserted or removed.
nonisolated enum ChangeSides: Sendable {
    case both
    /// Only the staged files (the working lane of the Lanes layout).
    case staged
    /// Only the unstaged files (the left card of the Lanes layout).
    case unstaged

    var showsStaged: Bool { self != .unstaged }
    var showsUnstaged: Bool { self != .staged }
}

/// Staged and unstaged files as collapsible sections of folders, with the commit box underneath.
/// Space stages or unstages the selected files. Body: O(shown rows), at most 500 per section (`CappedRows`).
struct ChangesSidebar: View {
    let repository: RepositoryModel
    let app: AppModel
    /// The Classic sidebar shows both sections and the commit box; the other layouts take parts of it.
    var sides: ChangeSides = .both
    var showsCommitBox = true
    @State private var discarding: [GitChange] = []
    @State private var picked: Set<ChangeSelection> = []
    /// Sections and folders the user closed; everything is open by default.
    @State private var collapsed: Set<String> = []
    @AppStorage("changes.showsTree") private var showsTree = true

    private var changes: ChangesModel { repository.changes }
    private var staged: [GitChange] { repository.changeListing.staged }
    private var unstaged: [GitChange] { repository.changeListing.unstaged }

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
            // Both sections stay in the list while there is anything to show, even when one of them is empty.
            // Inserting and removing the first section of a sidebar List shifts the second one, and the outline view
            // behind it then misplaces headers and rows (the "sometimes wrong" stage/unstage layout).
            List(selection: Binding(get: { picked }, set: { pick($0) })) {
                if !repository.status.isClean {
                    // `sides` never changes for one list, so these conditions never insert or remove a section.
                    if sides.showsStaged {
                        section("Staged", key: "section:staged", changes: staged, tree: repository.changeListing.stagedTree, isStaged: true, action: "Unstage All") {
                            app.run { try await changes.unstageAll() }
                        }
                    }
                    if sides.showsUnstaged {
                        section("Changes", key: "section:unstaged", changes: unstaged, tree: repository.changeListing.unstagedTree, isStaged: false, action: "Stage All") {
                            app.run { try await changes.stageAll() }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            // The card behind the list gives the background, wherever the list is placed (sidebar column, lane,
            // inline card, floating panel); the sidebar style's own grey would show inside white cards.
            .scrollContentBackground(.hidden)
            // An overlay, not a row: a row's height is cached by the list and goes stale when the tree turns clean.
            .overlay {
                if repository.status.isClean {
                    ContentUnavailableView("No changes", systemImage: "checkmark.circle",
                                           description: Text("The working tree matches the last commit."))
                }
            }
            .accessibilityIdentifier("changes-list")
            .onKeyPress(.space) { toggleStage() }
            .onDeleteCommand(perform: discardSelected)
            // `initial`: a list made while a file is already selected (another layout, the pop-out diff, coming back to
            // Changes) highlights it at once, so Space works without clicking the row again.
            .onChange(of: changes.selection, initial: true) { syncPicked() }
            if showsCommitBox {
                Divider()
                CommitBox(repository: repository, app: app)
            }
        }
        .confirmationDialog(
            discarding.count == 1 ? "Discard changes to \(discarding[0].path)?" : "Discard \(discarding.count) changes?",
            isPresented: Binding(get: { !discarding.isEmpty }, set: { if !$0 { discarding = [] } }),
            titleVisibility: .visible
        ) {
            Button("Discard Changes") {
                let targets = discarding
                app.run { try await changes.discard(targets) }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("This cannot be undone. Untracked files are deleted.")
        }
    }

    // MARK: - Sections

    private func section(_ title: String, key: String, changes list: [GitChange], tree: [PathNode<GitChange>], isStaged: Bool, action: String,
                         perform: @escaping () -> Void) -> some View {
        Section(isExpanded: expansion(key)) {
            if showsTree {
                ChangeTreeRows(nodes: tree, isStaged: isStaged, repository: repository, app: app,
                               discarding: $discarding, collapsed: $collapsed)
            } else {
                CappedRows(items: list, id: { ChangeSelection(path: $0.path, staged: isStaged) }) { change in
                    ChangeRow(change: change, staged: isStaged, showsFolder: true, app: app, repository: repository, discarding: $discarding)
                        .tag(ChangeSelection(path: change.path, staged: isStaged))
                }
            }
        } header: {
            HStack {
                Text("\(title) · \(list.count)")
                Spacer()
                Button(action, action: perform)
                    .buttonStyle(.link)
                    .disabled(list.isEmpty)
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
            + (showsTree ? folders(repository.changeListing.stagedTree, prefix: "staged:")
                + folders(repository.changeListing.unstagedTree, prefix: "unstaged:") : [])
    }

    // MARK: - Selection and the space key

    /// One selected file shows its diff; several are kept for staging them together.
    private func pick(_ selection: Set<ChangeSelection>) {
        picked = selection
        if selection.count == 1, let only = selection.first, !only.isFolder {
            Task { await changes.select(only) }
        } else if selection.isEmpty {
            Task { await changes.select(nil) }
        }
    }

    /// The model moves the selection when a staged file changes lists; follow it. A file that is no longer selected
    /// (closed in another layout, or gone after a commit) loses its highlight, so clicking it again selects it again.
    /// A list that shows only one side ignores a selection on the other side, so Space in it can never stage or
    /// unstage a file it does not list.
    private func syncPicked() {
        guard let selection = changes.selection, shows(selection) else {
            if picked.count == 1, picked.first?.isFolder == false { picked = [] }
            return
        }
        if !picked.contains(selection) { picked = [selection] }
    }

    private func shows(_ selection: ChangeSelection) -> Bool {
        selection.staged ? sides.showsStaged : sides.showsUnstaged
    }

    /// The selected files, with every file below a selected folder, each once.
    private func selectedFiles() -> [(ChangeSelection, GitChange)] {
        var seen = Set<ChangeSelection>()
        let files = picked.flatMap { selection -> [(ChangeSelection, GitChange)] in
            guard selection.isFolder else { return changes.change(for: selection).map { [(selection, $0)] } ?? [] }
            return (selection.staged ? staged : unstaged).filter { $0.path.hasPrefix(selection.path) }
                .map { (ChangeSelection(path: $0.path, staged: selection.staged), $0) }
        }
        return files.filter { seen.insert($0.0).inserted }
    }

    /// Stages the selected unstaged files and unstages the selected staged ones; a selected folder stands for its files.
    /// Delete: asks to discard the selected files that are not staged (a staged file has to be unstaged first).
    private func discardSelected() {
        let targets = selectedFiles().filter { !$0.0.staged }.map(\.1)
        guard !targets.isEmpty else { return }
        discarding = targets
    }

    private func toggleStage() -> KeyPress.Result {
        let targets = selectedFiles()
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
        // The same path (file or folder) can be a row in both sections; its identity must say which, or the outline
        // view reuses a row that moved between them (stale highlight, disclosure state or position).
        CappedRows(items: nodes, id: { ChangeSelection(path: $0.id, staged: isStaged, isFolder: $0.isFolder) }) { node in
            if let change = node.item {
                ChangeRow(change: change, staged: isStaged, showsFolder: false, app: app, repository: repository, discarding: $discarding)
                    .tag(ChangeSelection(path: change.path, staged: isStaged))
            } else {
                DisclosureGroup(isExpanded: expansion(node)) {
                    ChangeTreeRows(nodes: node.children ?? [], isStaged: isStaged, repository: repository, app: app,
                                   discarding: $discarding, collapsed: $collapsed)
                } label: {
                    folderLabel(node)
                }
                .tag(ChangeSelection(path: node.id, staged: isStaged, isFolder: true))
            }
        }
    }

    private func key(_ node: PathNode<GitChange>) -> String { (isStaged ? "staged:" : "unstaged:") + node.id }

    private func expansion(_ node: PathNode<GitChange>) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(key(node)) }, set: { open in
            if open { collapsed.remove(key(node)) } else { collapsed.insert(key(node)) }
        })
    }

    private func toggle(_ files: [GitChange]) {
        app.run {
            if isStaged {
                try await repository.changes.unstage(files.flatMap { [$0.path] + ($0.originalPath.map { [$0] } ?? []) })
            } else {
                try await repository.changes.stage(files.map(\.path))
            }
        }
    }

    private func folderLabel(_ node: PathNode<GitChange>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").foregroundStyle(.theme(.textSubtle))
            Text(node.name).lineLimit(1).truncationMode(.middle)
                .accessibilityIdentifier("folder-\(isStaged ? "staged" : "unstaged")-\(node.id)")
            Text("\(node.itemCount)").font(.caption.monospacedDigit()).foregroundStyle(.theme(.textSubtle))
            Spacer(minLength: 4)
            Button { toggle(node.items) } label: {
                Image(systemName: isStaged ? "minus.circle" : "plus.circle")
            }
            .buttonStyle(.borderless)
            .help(isStaged ? "Unstage every file in \(node.name) (Space)" : "Stage every file in \(node.name) (Space)")
            .accessibilityIdentifier("\(isStaged ? "unstage" : "stage")-folder-\(node.id)")
            if !isStaged {
                Button { discarding = node.items } label: { Image(systemName: "arrow.uturn.backward.circle") }
                    .buttonStyle(.borderless)
                    .help("Discard the changes to every file in \(node.name)")
                    .accessibilityIdentifier("discard-folder-\(node.id)")
            }
        }
        .contextMenu {
            Button(isStaged ? "Unstage Folder" : "Stage Folder") { toggle(node.items) }
            if !isStaged {
                Button("Discard Changes in Folder…", role: .destructive) { discarding = node.items }
            }
        }
    }
}

/// Rows of a long list, a page at a time. A List asked to hold tens of thousands of rows at once stops responding,
/// so the rest waits behind a "Show more" row. Builds O(shown) rows; `id` must be unique across the whole List.
private struct CappedRows<Item, ID: Hashable, Row: View>: View {
    private static var pageSize: Int { 500 }

    let items: [Item]
    let id: (Item) -> ID
    @ViewBuilder let row: (Item) -> Row
    @State private var shown = pageSize

    var body: some View {
        // A lazy map: the keyed rows are made as the List asks for them, with no copy of the page.
        ForEach(items.prefix(shown).lazy.map { KeyedRow(id: id($0), item: $0) }) { row($0.item) }
        if items.count > shown {
            Button("Show \(min(Self.pageSize, items.count - shown)) more · \(items.count - shown) hidden") {
                shown += Self.pageSize
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}

private struct KeyedRow<ID: Hashable, Item>: Identifiable {
    let id: ID
    let item: Item
}

#if DEBUG
#Preview("Changes sidebar") {
    PreviewRepository(width: 340, height: 600) { repository, app in
        ChangesSidebar(repository: repository, app: app)
    }
}
#endif
