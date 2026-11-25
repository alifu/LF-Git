import LFKit
import SwiftUI

/// Local and remote branches in separate panels, each with its own search box. The remote panel starts folded so a
/// stray click lands on a local branch. Double-click checks a branch out; every other action is in the context menu.
struct BranchesSidebar: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel
    @State private var localQuery = ""
    @State private var remoteQuery = ""
    @AppStorage(LayoutPreferences.listsKey) private var listsLayout = ListsLayout.default.rawValue
    @State private var scope = BranchScope.all
    /// The remote panel is folded until the user opens it.
    @State private var showsRemotes = false
    /// Remotes and folders the user closed; they are open by default.
    @State private var collapsed: Set<String> = []

    private var isThreeColumn: Bool { ListsLayout(stored: listsLayout) == .threeColumn }
    /// The scope only applies in the three-column layout; Classic always shows both panels.
    private var activeScope: BranchScope { isThreeColumn ? scope : .all }
    private var allLocals: [GitBranch] { repository.branches.filter { !$0.isRemote } }
    private var allRemotes: [GitBranch] { repository.branches.filter(\.isRemote) }
    private var locals: [GitBranch] { BranchMenuFilter.matching(allLocals, query: localQuery, name: \.name) }
    private var remotes: [GitBranch] { BranchMenuFilter.matching(allRemotes, query: remoteQuery, name: \.name) }
    private var localSearchText: String { localQuery.trimmingCharacters(in: .whitespaces) }
    private var remoteSearchText: String { remoteQuery.trimmingCharacters(in: .whitespaces) }
    /// Picking Remote in the scope picker shows the remote list open; otherwise it is as the user left it.
    private var isRemoteOpen: Bool { activeScope == .remote || showsRemotes }
    private var showsRemotePanel: Bool { activeScope.showsRemote && (activeScope == .remote || !allRemotes.isEmpty) }
    private var currentTarget: CurrentTarget {
        let status = repository.status
        return CurrentTarget(branch: status.branch, upstream: status.upstream, ahead: status.ahead, behind: status.behind,
                             isDetached: status.isDetached)
    }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            if isThreeColumn {
                CurrentTargetRow(target: currentTarget)
                scopePicker
            }
            if activeScope.showsLocal { localPanel }
            if showsRemotePanel { remotePanel }
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
                .help("Open every folder")
                .accessibilityIdentifier("branches-expand-all")
            Button { collapsed = Set(allKeys) } label: { Label("", systemImage: "chevron.up.2") }
                .help("Close every folder")
                .accessibilityIdentifier("branches-collapse-all")
        }
        .frame(maxWidth: .infinity)
    }

    private var scopePicker: some View {
        Picker("Show", selection: $scope) {
            ForEach(BranchScope.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .accessibilityIdentifier("branch-scope")
    }

    private func searchField(_ prompt: String, text: Binding<String>, id: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.theme(.textSubtle))
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier(id)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Clear the search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func panelTitle(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count)").font(.caption.weight(.semibold)).foregroundStyle(.theme(.textSubtle))
    }

    // MARK: - Local

    private var localPanel: some View {
        VStack(spacing: 0) {
            panelTitle("Local", count: locals.count)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            searchField("Search local branches", text: $localQuery, id: "branch-search")
            branchList(emptySearch: locals.isEmpty ? localSearchText : "") { localRows }
                .accessibilityIdentifier("branches-list")
        }
    }

    @ViewBuilder
    private var localRows: some View {
        if localSearchText.isEmpty {
            BranchTreeRows(nodes: PathNode.build(locals, path: { $0.name }), keyPrefix: "local:", collapsed: $collapsed,
                           row: { row($0, title: $1) })
        } else {
            ForEach(locals) { branch in row(branch, title: branch.name).tag(branch.id) }
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

    /// Set apart on a raised background, behind a header the user clicks to open.
    private var remotePanel: some View {
        VStack(spacing: 0) {
            Divider()
            remoteHeader
            if isRemoteOpen {
                searchField("Search remote branches", text: $remoteQuery, id: "branch-remote-search")
                branchList(emptySearch: remotes.isEmpty ? remoteSearchText : "") { remoteRows }
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier("branches-remote-list")
            }
        }
        .background(.theme(.surfaceRaised))
    }

    private var remoteHeader: some View {
        Button { showsRemotes.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isRemoteOpen ? 90 : 0))
                    .foregroundStyle(.theme(.textSubtle))
                Image(systemName: "cloud").foregroundStyle(.theme(.textSubtle))
                panelTitle("Remote", count: remotes.count)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(activeScope == .remote)
        .help(isRemoteOpen ? "Hide remote branches" : "Show remote branches")
        .accessibilityIdentifier("branches-remote-toggle")
    }

    @ViewBuilder
    private var remoteRows: some View {
        let byRemote = Dictionary(grouping: remotes, by: remoteName(of:))
        let names = byRemote.keys.sorted()
        if !remoteSearchText.isEmpty {
            ForEach(remotes) { branch in row(branch, title: nameOnRemote(branch)).tag(branch.id) }
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
    }

    // MARK: - Rows and helpers

    /// One panel's list: shared selection, context menu and double-click checkout. `emptySearch` is the search text
    /// when nothing matches it, or empty when there is nothing to report.
    private func branchList<Rows: View>(emptySearch: String, @ViewBuilder rows: () -> Rows) -> some View {
        List(selection: $repository.branchSelection) { rows() }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let branch = branch(withID: ids.first) {
                    BranchContextMenu(repository: repository, app: app, branch: branch)
                }
            } primaryAction: { ids in
                if ids.count == 1, let branch = branch(withID: ids.first) { checkOut(branch) }
            }
            .overlay {
                if !emptySearch.isEmpty { ContentUnavailableView.search(text: emptySearch) }
            }
    }

    private func row(_ branch: GitBranch, title: String) -> some View {
        BranchRow(branch: branch, title: title)
    }

    private func expansion(_ key: String) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(key) }, set: { open in
            if open { collapsed.remove(key) } else { collapsed.insert(key) }
        })
    }

    /// Every remote and folder, for "Collapse All". The remote panel itself keeps its own toggle.
    private var allKeys: [String] {
        func folders(_ nodes: [PathNode<GitBranch>], prefix: String) -> [String] {
            nodes.filter(\.isFolder).flatMap { [prefix + $0.id] + folders($0.children ?? [], prefix: prefix) }
        }
        var keys = folders(PathNode.build(allLocals, path: { $0.name }), prefix: "local:")
        for (name, branches) in Dictionary(grouping: allRemotes, by: remoteName(of:)) {
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

/// The pinned summary above the list: the checked-out branch, its upstream and how far apart they are.
private struct CurrentTargetRow: View {
    let target: CurrentTarget

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope").foregroundStyle(.theme(.accent)).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(target.title).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                Text(target.detail).font(.caption).foregroundStyle(.theme(.textSubtle)).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            TrackingBadge(ahead: target.ahead, behind: target.behind)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.theme(.surfaceRaised))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("current-target")
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
    @AppStorage(LayoutPreferences.listsKey) private var listsLayout = ListsLayout.default.rawValue

    private var history: HistoryModel { repository.branchHistory }

    var body: some View {
        if ListsLayout(stored: listsLayout) == .threeColumn {
            JoinedCards {
                CommitListView(repository: repository, app: app, model: history)
            } trailing: {
                preview
            }
            .accessibilityIdentifier("branches-three-column")
        } else {
            HSplitView {
                CommitListView(repository: repository, app: app, model: history)
                    .frame(minWidth: 300, idealWidth: 380)
                HistoryDetailView(repository: repository, app: app, model: history)
                    .frame(minWidth: 320)
            }
            .background(.theme(.background))
        }
    }

    @ViewBuilder
    private var preview: some View {
        if history.selectedCommit == nil && history.comparison == nil {
            EmptyPane("Select something to preview", symbol: "doc.text.magnifyingglass",
                      message: "Pick a commit to see its files and diff.")
                .background(DotGridBackground())
        } else {
            HistoryDetailView(repository: repository, app: app, model: history)
        }
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
