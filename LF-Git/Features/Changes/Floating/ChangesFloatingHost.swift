import SwiftUI

/// Owns the floating panels (L5) of the Changes section in every layout, Classic included: hands the open/close state
/// to the pop-out buttons through the environment and draws the open panels over `content`.
/// Body: O(1) plus the open panels (a capped file list and the diff table, O(visible rows)).
struct ChangesFloatingHost<Content: View>: View {
    let repository: RepositoryModel
    let app: AppModel
    /// Panels show only while the Changes section is on screen; their state is kept while away.
    let isActive: Bool
    let content: Content
    @State private var floating = FloatingPanels.none

    // Figma "Floating diff" 860×627 and "Floating window" 620×272.
    private static var diffSize: CGSize { CGSize(width: 860, height: 627) }
    private static var editorSize: CGSize { CGSize(width: 620, height: 300) }
    private static var editorStartOffset: CGSize { CGSize(width: 0, height: 140) }

    init(repository: RepositoryModel, app: AppModel, isActive: Bool, @ViewBuilder content: () -> Content) {
        self.repository = repository
        self.app = app
        self.isActive = isActive
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.changesFloating, $floating)
            .overlay {
                if isActive && floating != .none {
                    GeometryReader { geometry in
                        panels(in: geometry.size)
                    }
                    .environment(\.changesFloating, $floating)
                }
            }
    }

    @ViewBuilder
    private func panels(in container: CGSize) -> some View {
        if floating.showsDiff {
            FloatingPanel(id: "diff", title: diffTitle, size: Self.diffSize, container: container,
                          onClose: { floating = floating.with(diff: false) }) {
                FloatingDiffContent(repository: repository, app: app)
            }
        }
        if floating.showsEditor {
            FloatingPanel(id: "commit-editor", title: "Commit Message", size: Self.editorSize, container: container,
                          initialOffset: Self.editorStartOffset, onClose: { floating = floating.with(editor: false) }) {
                CommitBox(repository: repository, app: app, isFloating: true)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(.theme(.surfaceRaised))
            }
        }
    }

    private var diffTitle: String {
        repository.changes.selection?.staged == true ? "Staged Changes" : "Changes"
    }
}

/// The popped-out diff: the files of the selected file's side beside its diff (Figma "Floating diff").
/// Body: O(shown rows) for the list (capped) and O(visible rows) for the diff.
private struct FloatingDiffContent: View {
    let repository: RepositoryModel
    let app: AppModel

    private var side: ChangeSides { repository.changes.selection?.staged == true ? .staged : .unstaged }

    var body: some View {
        JoinedCards(leadingWidth: Chrome.listColumn...Chrome.listColumn) {
            ChangesSidebar(repository: repository, app: app, sides: side, showsCommitBox: false)
                // A new list per side, so a section is never swapped inside one list.
                .id(side)
        } trailing: {
            ChangesDetailView(repository: repository, app: app, allowsPopOut: false)
        }
    }
}
