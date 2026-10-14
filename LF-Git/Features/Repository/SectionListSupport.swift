import LFKit
import SwiftUI

/// A list row with a symbol, a title, a subtitle and optional trailing text.
struct SimpleRow: View {
    let symbol: String
    var symbolToken: LFThemeToken = .accentText
    let title: String
    var subtitle: String?
    var trailing: String?
    var identifier: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.theme(symbolToken)).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1).truncationMode(.middle)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.theme(.textSubtle)).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing).font(.caption.monospaced()).foregroundStyle(.theme(.textSubtle))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// A small bar of buttons above a list.
struct ListActionBar<Content: View>: View {
    /// Pushes the buttons to the leading edge. Pass `false` when the content places its own `Spacer` (or fills the width).
    let hasTrailingSpacer: Bool
    let content: Content

    init(hasTrailingSpacer: Bool = true, @ViewBuilder content: () -> Content) {
        self.hasTrailingSpacer = hasTrailingSpacer
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
            if hasTrailingSpacer { Spacer() }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension View {
    /// Shows the commit of a list row in the commit viewer when the selection changes.
    func emptyOverlay(_ isEmpty: Bool, _ title: String, symbol: String) -> some View {
        overlay {
            if isEmpty { ContentUnavailableView(title, systemImage: symbol) }
        }
    }
}

#Preview("Rows") {
    List {
        SimpleRow(symbol: "tag", title: "v1.0", subtitle: "First release", trailing: "a1b2c3d", identifier: "preview-row-1")
        SimpleRow(symbol: "arrow.triangle.branch", symbolToken: .accentText, title: "feature/greeting",
                  subtitle: "origin/feature/greeting", identifier: "preview-row-2")
    }
    .frame(width: 340, height: 160)
}
