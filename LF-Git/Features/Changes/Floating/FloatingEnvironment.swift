import SwiftUI

extension EnvironmentValues {
    /// The floating panels over the Changes section, owned by `ChangesFloatingHost`. Outside a host the constant
    /// default keeps every pop-out button harmless.
    @Entry var changesFloating: Binding<FloatingPanels> = .constant(.none)
}

/// "Moved to a floating panel" in place of a docked piece, with a button that brings it back. O(1).
struct PoppedOutNotice: View {
    let title: String
    let symbol: String
    let identifier: String
    let bringBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.theme(.textSubtle))
            Text(title).font(.callout).foregroundStyle(.theme(.textSubtle))
            Spacer(minLength: 4)
            Button("Bring Back", action: bringBack)
                .buttonStyle(.link)
                .accessibilityIdentifier(identifier)
        }
        .padding(10)
        .background(.theme(.surfaceRaised))
    }
}
