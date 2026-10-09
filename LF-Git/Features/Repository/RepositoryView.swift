import LFKit
import SwiftUI

/// The sidebar and detail of one repository window.
struct RepositoryView: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel
    @State private var promptText = ""
    @State private var messageText = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SectionGrid(repository: repository)
                Divider()
                sidebar
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        OperationBanner(repository: repository, app: app)
                        BisectBanner(repository: repository, app: app)
                    }
                }
        }
        .navigationTitle(repository.name)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                BranchMenu(repository: repository, app: app)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                RemoteButtons(repository: repository, app: app)
                Button {
                    Task { await repository.refresh(reloadDiffs: true) }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload (⌘R)")
                Button { repository.showsPalette = true } label: {
                    Label("Commands", systemImage: "command")
                }
                .help("Command palette (⌘K)")
                .accessibilityIdentifier("palette-button")
            }
        }
        .focusedSceneValue(\.repositoryModel, repository)
        .onAppear { repository.startWatching() }
        .onDisappear { repository.stopWatching() }
        .modifier(RepositoryDialogs(repository: repository, app: app, promptText: $promptText, messageText: $messageText))
    }

    @ViewBuilder
    private var sidebar: some View {
        switch repository.section {
        case .changes: ChangesSidebar(repository: repository, app: app)
        case .branches: BranchesSidebar(repository: repository, app: app)
        case .history: HistorySidebar(repository: repository, app: app)
        case .stash: StashSidebar(repository: repository, app: app)
        case .tags: TagsSidebar(repository: repository, app: app)
        case .remotes: RemotesSidebar(repository: repository, app: app)
        case .reflog: ReflogSidebar(repository: repository, app: app)
        case .worktrees: WorktreesSidebar(repository: repository, app: app)
        case .submodules: SubmodulesSidebar(repository: repository, app: app)
        case .conflicts: ConflictsSidebar(repository: repository)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch repository.section {
        case .changes:
            ChangesDetailView(repository: repository, app: app)
        case .branches:
            BranchesDetail(repository: repository, app: app)
        case .history:
            HistoryDetailView(repository: repository, app: app, model: repository.history)
        case .stash:
            CommitViewerDetail(repository: repository, app: app, emptyTitle: "Select a stash")
        case .tags:
            CommitViewerDetail(repository: repository, app: app, emptyTitle: "Select a tag")
        case .reflog:
            CommitViewerDetail(repository: repository, app: app, emptyTitle: "Select a reflog entry")
        case .remotes:
            RemotesDetail(repository: repository, app: app)
        case .worktrees:
            ContentUnavailableView("Worktrees", systemImage: "square.stack.3d.up",
                                   description: Text("Each worktree is another checkout of this repository. Right-click one to open it."))
                .background(.theme(.background))
        case .submodules:
            ContentUnavailableView("Submodules", systemImage: "shippingbox",
                                   description: Text("Repositories nested inside this one. Right-click one to update or open it."))
                .background(.theme(.background))
        case .conflicts:
            if let file = repository.selectedFile {
                FileDetailView(repository: repository, file: file, app: app)
                    .id(file.id)
            } else {
                ContentUnavailableView(
                    repository.files.isEmpty ? "No conflicts" : "Select a file",
                    systemImage: repository.files.isEmpty ? "checkmark.seal" : "doc.text",
                    description: Text(repository.files.isEmpty
                        ? "Every conflicted file in \(repository.name) is resolved."
                        : "Choose a conflicted file in the sidebar.")
                )
                .background(.theme(.background))
            }
        }
    }
}

/// The sections as a grid of small buttons, with counts.
struct SectionGrid: View {
    let repository: RepositoryModel

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 4)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(RepositorySection.allCases) { section in
                Button {
                    repository.section = section
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: section.symbol).frame(width: 14)
                        Text(section.rawValue).lineLimit(1)
                        if let count = count(section), count > 0 {
                            Text("\(count)").font(.caption2.monospacedDigit().weight(.semibold))
                        }
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.theme(repository.section == section ? .accentSubtle : .surfaceRaised)))
                    .foregroundStyle(.theme(repository.section == section ? .accentText : .text))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(repository.section == section ? .isSelected : [])
                .accessibilityIdentifier("section-\(section.rawValue)")
            }
        }
        .padding(8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("section-picker")
    }

    private func count(_ section: RepositorySection) -> Int? {
        switch section {
        case .changes: repository.status.entries.filter { $0.kind != .unmerged }.count
        case .stash: repository.stashes.count
        case .conflicts: repository.files.count
        default: nil
        }
    }
}

struct ConflictsSidebar: View {
    @Bindable var repository: RepositoryModel

    var body: some View {
        List(selection: $repository.selection) {
            Section {
                ForEach(repository.files) { file in
                    FileRow(file: file).tag(file.id)
                }
            } header: {
                Text(repository.files.isEmpty ? "No conflicted files" : "\(repository.files.count) conflicted")
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if repository.isLoading && repository.files.isEmpty {
                ProgressView()
            }
        }
        .accessibilityIdentifier("conflicted-files")
    }
}

private struct FileRow: View {
    let file: ConflictedFile

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.theme(file.kind == .binary ? .warning : .accentText))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).lineLimit(1)
                if !file.folder.isEmpty {
                    Text(file.folder)
                        .font(.caption)
                        .foregroundStyle(.theme(.textSubtle))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            badge
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("file-\(file.path)")
    }

    private var icon: String {
        switch file.kind {
        case .text: "doc.text"
        case .project: "hammer"
        case .binary: "photo"
        }
    }

    @ViewBuilder
    private var badge: some View {
        if file.problem != nil {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.theme(.danger))
        } else if file.kind == .binary {
            Text("binary").font(.caption).foregroundStyle(.theme(.textSubtle))
        } else if file.conflictCount > 0 {
            Text("\(file.conflictCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(.theme(.danger)))
                .foregroundStyle(.theme(.onAccent))
                .accessibilityLabel("\(file.conflictCount) conflicts")
        } else {
            Image(systemName: "checkmark").foregroundStyle(.theme(.accentText)).accessibilityLabel("no markers left")
        }
    }
}
