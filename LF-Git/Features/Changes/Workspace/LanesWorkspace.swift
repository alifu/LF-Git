import LFKit
import SwiftUI

/// Lanes (L3): the unstaged files in a list card, then a dotted canvas that scrolls sideways with the working lane
/// and, beside it, one detail panel (a file's diff or a commit preview). Body: O(lanes + panels) on the canvas,
/// each lazily built, plus the capped unstaged list.
struct LanesWorkspace: View {
    let repository: RepositoryModel
    let app: AppModel
    @Binding var panels: WorkspacePanels

    var body: some View {
        HStack(spacing: Chrome.gutter) {
            VStack(spacing: 0) {
                CardHeader("Unstaged", symbol: RepositorySection.changes.symbol,
                           count: repository.changeListing.unstaged.count)
                ChangesSidebar(repository: repository, app: app, sides: .unstaged, showsCommitBox: false)
            }
            .frame(width: Chrome.listColumn)
            .lfCard()
            LaneCanvas(repository: repository, app: app, panels: $panels)
                .lfCard()
        }
    }
}

/// The canvas: `ScrollView(.horizontal)` over the dot grid with the lane and its panel, and a minimap pill once
/// they are wider than the view. Body: O(lanes + panels), minimap O(lanes).
private struct LaneCanvas: View {
    let repository: RepositoryModel
    let app: AppModel
    @Binding var panels: WorkspacePanels

    private static var laneID: String { "lane" }
    private static var panelID: String { "panel" }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: WorkspacePanels.laneSpacing) {
                        WorkingLane(repository: repository, app: app, selectedCommit: selectedCommit,
                                    onSelectCommit: open)
                            .id(Self.laneID)
                        if let detail = panels.detail {
                            panel(detail)
                                .id(Self.panelID)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .padding(WorkspacePanels.canvasPadding)
                    .frame(height: geometry.size.height)
                }
                .background(DotGridBackground())
                .overlay(alignment: .bottomTrailing) {
                    if WorkspacePanels.showsMinimap(contentWidth: panels.canvasContentWidth, viewportWidth: geometry.size.width) {
                        LaneMinimap(hasPanel: panels.isOpen) { target in
                            withAnimation { proxy.scrollTo(target == .panel ? Self.panelID : Self.laneID, anchor: .leading) }
                        }
                        .padding(WorkspacePanels.canvasPadding)
                    }
                }
                .onChange(of: panels.detail) {
                    guard panels.isOpen else { return }
                    withAnimation { proxy.scrollTo(Self.panelID, anchor: .trailing) }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: panels)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lanes-canvas")
    }

    private var selectedCommit: GitCommit.ID? {
        if case .commit(let id) = panels.detail { return id }
        return nil
    }

    @ViewBuilder
    private func panel(_ detail: WorkspacePanels.Detail) -> some View {
        switch detail {
        case .file:
            ChangesDetailView(repository: repository, app: app, onClose: closeFile)
                .frame(width: Chrome.panelWidth)
                .lfCard()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("lane-file-panel")
        case .commit:
            CommitPreviewPanel(repository: repository, app: app) { panels = panels.closing() }
                .frame(width: Chrome.panelWidth)
                .lfCard()
        }
    }

    /// A commit replaces the file panel; the file loses its selection so clicking it again reopens it.
    private func open(_ commit: GitCommit) {
        panels = panels.opening(.commit(commit.id))
        Task {
            await repository.changes.select(nil)
            await repository.history.select(commit.id)
        }
    }

    private func closeFile() {
        panels = panels.closing()
        Task { await repository.changes.select(nil) }
    }
}

/// A commit's files and diff beside the lane (Figma "Commit preview"), reusing the History detail. O(files shown)
/// for the list, O(visible rows) for the diff.
private struct CommitPreviewPanel: View {
    let repository: RepositoryModel
    let app: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CardHeader("Commit", symbol: "smallcircle.filled.circle") {
                Text(repository.history.selectedCommit?.shortHash ?? "")
                    .font(.caption.monospaced()).foregroundStyle(.theme(.textSubtle))
                CloseButton(label: "Close Commit Preview", action: onClose)
            }
            HistoryDetailView(repository: repository, app: app, model: repository.history, forcesStacked: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lane-commit-panel")
    }
}

/// The minimap pill (bottom right): one block per lane or panel; a click scrolls to it. O(lanes).
private struct LaneMinimap: View {
    enum Target { case lane, panel }

    let hasPanel: Bool
    let scroll: (Target) -> Void

    var body: some View {
        HStack(spacing: 3) {
            block(.lane, width: 14, label: "Scroll to the lane")
            if hasPanel { block(.panel, width: 18, label: "Scroll to the panel") }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(.theme(.background)))
        .overlay(Capsule().strokeBorder(.theme(.border)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lanes-minimap")
    }

    private func block(_ target: Target, width: CGFloat, label: String) -> some View {
        Button { scroll(target) } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(.theme(target == .lane ? .accent : .borderStrong))
                .frame(width: width, height: 10)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
