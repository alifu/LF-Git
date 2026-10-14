import LFKit
import SwiftUI

/// Local and remote branches in collapsible groups, with a search box. Double-click checks a branch out;
/// every other branch action is in the context menu.
struct BranchesSidebar: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel
    @State private var query = ""
    /// Sections, remotes and folders the user closed; everything is open by default.
    @State private var collapsed: Set<String> = []

    private var locals: [GitBranch] { repository.branches.filter { !$0.isRemote } }
    private var remotes: [GitBranch] { repository.branches.filter(\.isRemote) }
    private var searchText: String { query.trimmingCharacters(in: .whitespaces) }
    private var isSearching: Bool { !searchText.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            searchField
            List(selection: $repository.branchSelection) {
                localSection
                remoteSection
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("branches-list")
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let branch = branch(withID: ids.first) {
                    BranchContextMenu(repository: repository, app: app, branch: branch)
                }
            } primaryAction: { ids in
                if ids.count == 1, let branch = branch(withID: ids.first) { checkOut(branch) }
            }
            .overlay {
                if isSearching && matches(locals).isEmpty && matches(remotes).isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .onChange(of: repository.branchSelection, initial: true) { showHistory() }
        .onChange(of: repository.branches) { showHistory() }
    }

    // MARK: - Header

    private var actionBar: some View {
        ListActionBar(hasTrailingSpacer: false) {
            Button { newBranch(from: nil) } label: { Label("New Branch", systemImage: "plus") }
                .accessibilityIdentifier("new-branch")
            Button { app.run { try await repository.perform("Switching…") { client, _ in try client.switchPrevious() } } } label: {
                Label("Previous", systemImage: "arrow.uturn.backward")
            }
            .help("Check out the previously checked-out branch")
            Spacer()
            Button { collapsed = [] } label: { Label("", systemImage: "chevron.down.2") }
                .help("Open every group")
                .accessibilityIdentifier("branches-expand-all")
            Button { collapsed = Set(allKeys) } label: { Label("", systemImage: "chevron.up.2") }
                .help("Close every group")
                .accessibilityIdentifier("branches-collapse-all")
        }
        .frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.theme(.textSubtle))
            TextField("Search branches", text: $query)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("branch-search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Clear the search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Local

    @ViewBuilder
    private var localSection: some View {
        let shown = matches(locals)
        Section(isExpanded: expansion("section:local")) {
            if isSearching {
                ForEach(shown) { branch in row(branch, title: branch.name).tag(branch.id) }
            } else {
                BranchTreeRows(nodes: PathNode.build(shown, path: { $0.name }), keyPrefix: "local:", collapsed: $collapsed,
                               row: { row($0, title: $1) })
            }
        } header: {
            Text("Local · \(shown.count)")
        }
    }

    // MARK: - Remote

    /// The remote a branch lives on (`origin` for `origin/main`); remote names may contain a slash themselves.
    private func remoteName(of branch: GitBranch) -> String {
        let names = repository.remotes.map(\.name).filter { branch.name.hasPrefix($0 + "/") }
        return names.max { $0.count < $1.count } ?? branch.name.split(separator: "/").first.map(String.init) ?? branch.name
    }

    /// The branch's name on its remote: `main` for `origin/main`.
    private func nameOnRemote(_ branch: GitBranch) -> String {
        String(branch.name.dropFirst(remoteName(of: branch).count + 1))
    }

    @ViewBuilder
    private var remoteSection: some View {
        let shown = matches(remotes)
        if !remotes.isEmpty {
            Section(isExpanded: expansion("section:remote")) {
                let byRemote = Dictionary(grouping: shown, by: remoteName(of:))
                let names = byRemote.keys.sorted()
                if isSearching {
                    ForEach(shown) { branch in row(branch, title: nameOnRemote(branch)).tag(branch.id) }
                } else if names.count == 1, let only = names.first {
                    // One remote: its name would be the same word on every row, so the branches stand alone.
                    BranchTreeRows(nodes: PathNode.build(byRemote[only] ?? [], path: nameOnRemote), keyPrefix: "remote:\(only):",
                                   collapsed: $collapsed, row: { row($0, title: $1) })
                } else {
                    ForEach(names, id: \.self) { name in
                        DisclosureGroup(isExpanded: expansion("remote:\(name)")) {
                            BranchTreeRows(nodes: PathNode.build(byRemote[name] ?? [], path: nameOnRemote), keyPrefix: "remote:\(name):",
                                           collapsed: $collapsed, row: { row($0, title: $1) })
                        } label: {
                            Label("\(name) · \(byRemote[name]?.count ?? 0)", systemImage: "externaldrive.connected.to.line.below")
                        }
                    }
                }
            } header: {
                Text("Remote · \(shown.count)")
            }
        }
    }

    // MARK: - Rows and helpers

    private func row(_ branch: GitBranch, title: String) -> some View {
        BranchRow(branch: branch, title: title)
    }

    private func matches(_ list: [GitBranch]) -> [GitBranch] {
        isSearching ? list.filter { $0.name.localizedCaseInsensitiveContains(searchText) } : list
    }

    private func expansion(_ key: String) -> Binding<Bool> {
        Binding(get: { isSearching || !collapsed.contains(key) }, set: { open in
            if open { collapsed.remove(key) } else { collapsed.insert(key) }
        })
    }

    /// Every group, for "Collapse All".
    private var allKeys: [String] {
        func folders(_ nodes: [PathNode<GitBranch>], prefix: String) -> [String] {
            nodes.filter(\.isFolder).flatMap { [prefix + $0.id] + folders($0.children ?? [], prefix: prefix) }
        }
        var keys = ["section:local", "section:remote"] + folders(PathNode.build(locals, path: { $0.name }), prefix: "local:")
        for (name, branches) in Dictionary(grouping: remotes, by: remoteName(of:)) {
            keys.append("remote:\(name)")
            keys += folders(PathNode.build(branches, path: nameOnRemote), prefix: "remote:\(name):")
        }
        return keys
    }

    private func branch(withID id: String?) -> GitBranch? {
        repository.branches.first { $0.id == id }
    }

    /// Double-click: switch to the branch (a remote one gets a local tracking branch).
    private func checkOut(_ branch: GitBranch) {
        guard !branch.isCurrent else { return }
        app.run { try await repository.perform("Switching to \(branch.name)…", cancellable: false) { client, _ in try client.switchBranch(branch.name) } }
    }

    private func showHistory() {
        let id = repository.branchSelection ?? repository.branches.first { $0.isCurrent }?.id
        guard let branch = repository.branches.first(where: { $0.id == id }) else { return }
        Task { await repository.branchHistory.show(.log(revision: branch.name)) }
    }

    private func newBranch(from start: String?) {
        repository.ask(PendingPrompt(title: "New Branch", message: start.map { "Created from \($0) and switched to." } ?? "Created from the current commit and switched to.",
                                     placeholder: "Branch name", confirmTitle: "Create") { name in
            app.run { try await repository.createBranch(name.trimmingCharacters(in: .whitespaces), from: start) }
        })
    }
}

/// Folders of branch names (`feature/login`) and the branches inside them, one level at a time.
private struct BranchTreeRows<Row: View>: View {
    let nodes: [PathNode<GitBranch>]
    /// Distinguishes this tree's folders from another tree's in `collapsed`.
    let keyPrefix: String
    @Binding var collapsed: Set<String>
    let row: (GitBranch, String) -> Row

    var body: some View {
        ForEach(nodes) { node in
            if let branch = node.item {
                row(branch, node.name).tag(branch.id)
            } else {
                DisclosureGroup(isExpanded: expansion(node)) {
                    BranchTreeRows(nodes: node.children ?? [], keyPrefix: keyPrefix, collapsed: $collapsed, row: row)
                } label: {
                    Label(node.name, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("branch-folder-\(node.id)")
                }
            }
        }
    }

    private func expansion(_ node: PathNode<GitBranch>) -> Binding<Bool> {
        let key = keyPrefix + node.id
        return Binding(get: { !collapsed.contains(key) }, set: { open in
            if open { collapsed.remove(key) } else { collapsed.insert(key) }
        })
    }
}

private struct BranchRow: View {
    let branch: GitBranch
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : (branch.isRemote ? "cloud" : "arrow.triangle.branch"))
                .foregroundStyle(.theme(branch.isCurrent ? .accent : .textSubtle))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(branch.isCurrent ? .semibold : .regular).lineLimit(1).truncationMode(.middle)
                if !branch.isRemote, let upstream = branch.upstream {
                    Text("tracks \(upstream)").font(.caption).foregroundStyle(.theme(.textSubtle)).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            if !branch.isRemote { TrackingBadge(ahead: branch.ahead, behind: branch.behind) }
            Text(branch.tip).font(.caption.monospaced()).foregroundStyle(.theme(.textSubtle))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("branch-\(branch.name)")
    }
}

/// How many commits a local branch would push (↑) or pull (↓), as of the last fetch.
struct TrackingBadge: View {
    let ahead: Int
    let behind: Int

    var body: some View {
        if ahead > 0 || behind > 0 {
            HStack(spacing: 4) {
                if behind > 0 { Text("↓\(behind)") }
                if ahead > 0 { Text("↑\(ahead)") }
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(.theme(.accentSubtle)))
            .foregroundStyle(.theme(.accentText))
            .help("\(behind) to pull, \(ahead) to push (as of the last fetch)")
            .accessibilityLabel("\(behind) to pull, \(ahead) to push")
        }
    }
}

/// The commits of the selected branch, and the selected commit.
struct BranchesDetail: View {
    let repository: RepositoryModel
    let app: AppModel

    var body: some View {
        HSplitView {
            CommitListView(repository: repository, app: app, model: repository.branchHistory)
                .frame(minWidth: 300, idealWidth: 380)
            HistoryDetailView(repository: repository, app: app, model: repository.branchHistory)
                .frame(minWidth: 320)
        }
        .background(.theme(.background))
    }
}

#if DEBUG
#Preview("Branches sidebar") {
    PreviewRepository(width: 340, height: 600) { repository, app in
        BranchesSidebar(repository: repository, app: app)
    }
}
#endif

#if DEBUG
#Preview("Branches detail") {
    PreviewRepository(width: 800, height: 600) { repository, app in
        BranchesDetail(repository: repository, app: app)
    }
}
#endif
