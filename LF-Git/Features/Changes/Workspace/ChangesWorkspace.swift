import SwiftUI

/// The Changes section when Settings › Layout picks a layout other than Classic. It owns the whole content area
/// (no split view): Inline preview (L4) or Lanes (L3). It keeps which detail panel is open (`WorkspacePanels`) and
/// follows the file selection of `ChangesModel`. Body: O(1) here; see `InlineWorkspace` and `LanesWorkspace`.
struct ChangesWorkspace: View {
    let repository: RepositoryModel
    let app: AppModel
    let layout: ChangesLayout
    @State private var panels = WorkspacePanels.closed

    var body: some View {
        Group {
            switch layout {
            case .lanes:
                LanesWorkspace(repository: repository, app: app, panels: $panels)
            case .inline, .classic:
                // Classic never reaches this view (RepositoryView shows the split view); Inline is the safe fallback.
                InlineWorkspace(repository: repository, app: app, panels: $panels)
            }
        }
        .safeAreaInset(edge: .top, spacing: Chrome.gutter) {
            VStack(spacing: 0) {
                OperationBanner(repository: repository, app: app)
                BisectBanner(repository: repository, app: app)
            }
        }
        .padding(Chrome.gutter)
        .onAppear { panels = panels.following(selectionFrom: nil, to: repository.changes.selection) }
        .onChange(of: repository.changes.selection) { old, new in
            panels = panels.following(selectionFrom: old, to: new)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("changes-workspace-\(layout.rawValue)")
    }
}
