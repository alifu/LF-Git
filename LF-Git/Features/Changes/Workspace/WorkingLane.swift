import LFKit
import SwiftUI

/// The one working lane of the Lanes layout (L3): the staged files, the commit box, and the checked-out branch with
/// its latest commits under a "your commit goes here" marker. LF-Git has no virtual branches, so there is one lane.
/// Body: O(shown staged rows) + O(`BranchContextCard.commitLimit`).
struct WorkingLane: View {
    let repository: RepositoryModel
    let app: AppModel
    let selectedCommit: GitCommit.ID?
    let onSelectCommit: (GitCommit) -> Void

    private static var stagedMinHeight: CGFloat { 140 }
    private static var branchHeight: CGFloat { 300 }

    var body: some View {
        VStack(spacing: Chrome.gutter) {
            VStack(spacing: 0) {
                CardHeader("Staged", symbol: "tray.full", count: repository.changeListing.staged.count) {
                    StagedSummary(changes: repository.changeListing.staged)
                }
                ChangesSidebar(repository: repository, app: app, sides: .staged, showsCommitBox: false)
                Divider()
                CommitBox(repository: repository, app: app)
            }
            .frame(minHeight: Self.stagedMinHeight, maxHeight: .infinity)
            .lfCard()
            BranchContextCard(repository: repository, app: app, showsUpcomingCommit: true,
                              onSelectCommit: onSelectCommit, selectedCommit: selectedCommit)
                .frame(height: Self.branchHeight)
        }
        .frame(width: Chrome.laneWidth)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("working-lane")
    }
}

/// How many staged files are new, modified and deleted ("+2 ~3 −1"). Git reports no line counts without another
/// command, so this counts files. O(n) for n staged files, run when the listing changes.
struct StagedSummary: View {
    let changes: [GitChange]

    var body: some View {
        let added = changes.count { [.added, .copied].contains($0.index) }
        let deleted = changes.count { $0.index == .deleted }
        let other = changes.count - added - deleted
        HStack(spacing: 4) {
            Text("+\(added)").foregroundStyle(.theme(.accentText))
            Text("~\(other)").foregroundStyle(.theme(.warning))
            Text("−\(deleted)").foregroundStyle(.theme(.danger))
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(added) new, \(other) changed, \(deleted) deleted")
    }
}
