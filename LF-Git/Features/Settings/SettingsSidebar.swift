import SwiftUI

/// The settings sidebar: a title and one row per tab, in a card like the side menu's panes.
struct SettingsSidebar: View {
    let selection: SettingsTab
    let select: (SettingsTab) -> Void

    private static let padding: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.theme(.text))
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            ForEach(SettingsTab.sidebarOrder) { tab in
                SettingsSidebarRow(tab: tab, isSelected: tab == selection) { select(tab) }
            }
            Spacer(minLength: 0)
        }
        .padding(Self.padding)
        .frame(maxHeight: .infinity, alignment: .top)
        .lfCard()
    }
}

/// One tab in the sidebar. The selected row takes the accent-subtle fill and a small accent mark on its leading edge.
private struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    private static let markWidth: CGFloat = 3
    private static let markHeight: CGFloat = 16
    private static let markOffset: CGFloat = -8

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .theme(.accentText) : .theme(.textSubtle))
                Text(tab.title)
                    .foregroundStyle(.theme(.text))
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Chrome.pillRadius)
                    .fill(isSelected ? .theme(.accentSubtle) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(.theme(.accentVivid))
                        .frame(width: Self.markWidth, height: Self.markHeight)
                        .offset(x: Self.markOffset)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
