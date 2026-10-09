import LFKit
import SwiftUI

/// Sections in the sidebar, and what each shows next to it.
struct RepositoryView: View {
    @Bindable var repository: RepositoryModel
    let app: AppModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sectionPicker
                Divider()
                sidebar
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 460)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    OperationBanner(repository: repository, app: app)
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
            }
        }
        .focusedSceneValue(\.repositoryModel, repository)
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $repository.section) {
            Text(label("Changes", repository.status.entries.filter { $0.kind != .unmerged }.count)).tag(RepositorySection.changes)
            Text("History").tag(RepositorySection.history)
            Text(label("Conflicts", repository.files.count)).tag(RepositorySection.conflicts)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(10)
        .accessibilityIdentifier("section-picker")
    }

    private func label(_ title: String, _ count: Int) -> String {
        count > 0 ? "\(title) \(count)" : title
    }

    @ViewBuilder
    private var sidebar: some View {
        switch repository.section {
        case .changes: ChangesSidebar(repository: repository, app: app)
        case .history: HistorySidebar(repository: repository)
        case .conflicts: ConflictsSidebar(repository: repository)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch repository.section {
        case .changes:
            ChangesDetailView(repository: repository, app: app)
        case .history:
            HistoryDetailView(repository: repository)
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
