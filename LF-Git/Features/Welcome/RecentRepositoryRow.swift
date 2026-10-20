import AppKit
import SwiftUI

/// One repository of the recent list: name, where it is, its branch and what is going on in it.
struct RecentRepositoryRow: View {
    let path: String
    let summary: RepositorySummary?
    let app: AppModel
    var prominent = false

    private var url: URL { URL(fileURLWithPath: path) }
    private var isMissing: Bool { summary?.isMissing == true }
    private var folder: String { (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isMissing ? "exclamationmark.triangle" : "shippingbox")
                .foregroundStyle(.theme(isMissing ? .warning : .accentText))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(url.lastPathComponent).font(prominent ? .headline : .body).lineLimit(1)
                    if let branch = summary?.branch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.theme(.textSubtle))
                            .lineLimit(1)
                    }
                }
                Text(folder).font(.caption).foregroundStyle(.theme(.textSubtle)).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            chips
            if prominent {
                Button("Open") { app.open(url) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMissing)
                    .accessibilityIdentifier("dashboard-open-last")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.theme(.surfaceRaised), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(count: prominent ? 2 : 1) { if !isMissing { app.open(url) } }
        .contextMenu {
            Button("Open") { app.open(url) }.disabled(isMissing)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.disabled(isMissing)
            Button("Copy Path") { Clipboard.copy(path) }
            Divider()
            Button("Remove from Recents") { app.removeFromRecents(path) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recent-\(path)")
    }

    @ViewBuilder
    private var chips: some View {
        if let summary {
            HStack(spacing: 6) {
                if summary.isMissing {
                    Chip(text: "missing", token: .warning)
                } else if summary.conflictCount > 0 {
                    Chip(text: summary.conflictCount == 1 ? "1 conflict" : "\(summary.conflictCount) conflicts", token: .danger)
                } else if summary.hasUnfinishedOperation {
                    Chip(text: "in progress", token: .danger)
                } else if summary.changeCount > 0 {
                    Chip(text: summary.changeCount == 1 ? "1 change" : "\(summary.changeCount.formatted()) changes", token: .warning)
                } else {
                    Chip(text: "clean", token: .textSubtle)
                }
                if summary.ahead > 0 { Chip(text: "↑\(summary.ahead)", token: .info) }
                if summary.behind > 0 { Chip(text: "↓\(summary.behind)", token: .info) }
            }
        }
    }
}

private struct Chip: View {
    let text: String
    let token: LFThemeToken

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(.theme(token))
            .background(.theme(token).opacity(0.14), in: Capsule())
    }
}
