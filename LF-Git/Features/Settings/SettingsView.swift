import SwiftUI

/// The tabs of the settings window. The selected one is remembered, so the side menu can open a given tab.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, account, network, environment, theme, layout

    static let storageKey = "settings.tab"
    /// The order of the sidebar rows.
    static let sidebarOrder: [SettingsTab] = [.general, .account, .network, .environment, .theme, .layout]

    var id: String { rawValue }

    /// Reads a stored name; anything unknown (or missing) opens General.
    init(stored: String?) {
        self = stored.flatMap(SettingsTab.init(rawValue:)) ?? .general
    }

    var title: String {
        switch self {
        case .general: "General"
        case .account: "Account"
        case .network: "Network"
        case .environment: "Environment"
        case .theme: "Theme"
        case .layout: "Layout"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .account: "person.crop.circle"
        case .network: "network"
        case .environment: "terminal"
        case .theme: "paintpalette"
        case .layout: "rectangle.3.group"
        }
    }
}

/// The settings window: a sidebar of topics beside one scrolling column of section cards.
struct SettingsView: View {
    @State private var git = GitSettingsModel()
    @AppStorage(SettingsTab.storageKey) private var tab = SettingsTab.general.rawValue

    private static let windowHeight: CGFloat = 560

    private var selection: SettingsTab { SettingsTab(stored: tab) }

    var body: some View {
        HStack(spacing: Chrome.gutter) {
            SettingsSidebar(selection: selection) { tab = $0.rawValue }
                .frame(width: Chrome.settingsSidebar)
            content(for: selection)
                .frame(width: Chrome.settingsContent)
        }
        .padding(Chrome.gutter)
        .frame(width: Chrome.settingsSidebar + Chrome.settingsContent + Chrome.gutter * 3, height: Self.windowHeight)
        .background(.theme(.surfaceSunken))
        .onAppear { git.load() }
    }

    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsTab()
        case .account: AccountSettingsTab(git: git)
        case .network: NetworkSettingsTab(git: git)
        case .environment: EnvironmentSettingsTab()
        case .theme: ThemeSettingsTab()
        case .layout: LayoutSettingsTab()
        }
    }
}

#Preview("Light") {
    SettingsView().preferredColorScheme(.light)
}

#Preview("Dark") {
    SettingsView().preferredColorScheme(.dark)
}
