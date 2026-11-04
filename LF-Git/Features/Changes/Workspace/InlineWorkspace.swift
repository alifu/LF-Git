import SwiftUI

/// Inline preview (L4): one card with the changes list that widens to show the selected file's diff beside it
/// (✕ closes it and the card shrinks back), and a second card with the commit box and the branch.
/// Body: O(shown rows) for the capped list, O(visible rows) for the diff, O(`BranchContextCard.commitLimit`).
struct InlineWorkspace: View {
    let repository: RepositoryModel
    let app: AppModel
    @Binding var panels: WorkspacePanels

    private static var contextWidth: CGFloat { 520 }
    private static var branchHeight: CGFloat { 320 }

    var body: some View {
        HStack(alignment: .top, spacing: Chrome.gutter) {
            changesCard
            contextCard
        }
        .animation(.easeInOut(duration: 0.2), value: panels.isFileOpen)
    }

    private var changesCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                CardHeader(RepositorySection.changes.rawValue, symbol: RepositorySection.changes.symbol,
                           count: repository.badgeCount(for: .changes))
                ChangesSidebar(repository: repository, app: app, showsCommitBox: false)
            }
            .frame(width: Chrome.listColumn)
            if panels.isFileOpen {
                Rectangle().fill(.theme(.border)).frame(width: 1)
                ChangesDetailView(repository: repository, app: app, onClose: closeDiff)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("inline-diff")
            }
        }
        .frame(width: panels.inlineCardWidth)
        .frame(maxHeight: .infinity)
        .lfCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inline-changes-card")
    }

    private var contextCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Chrome.gutter) {
                VStack(spacing: 0) {
                    CardHeader("Commit", symbol: "checkmark.circle")
                    CommitBox(repository: repository, app: app)
                }
                .lfCard()
                BranchContextCard(repository: repository, app: app)
                    .frame(height: Self.branchHeight)
            }
            .frame(maxWidth: Self.contextWidth)
            .padding(WorkspacePanels.canvasPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DotGridBackground())
        .lfCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inline-context-card")
    }

    private func closeDiff() {
        panels = panels.closing()
        Task { await repository.changes.select(nil) }
    }
}
