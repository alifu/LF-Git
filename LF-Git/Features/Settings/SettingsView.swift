import SwiftUI

/// The settings window: one tab per topic.
struct SettingsView: View {
    @State private var git = GitSettingsModel()

    var body: some View {
        TabView {
            AccountSettingsTab(git: git)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .accessibilityIdentifier("settings-tab-account")
            NetworkSettingsTab(git: git)
                .tabItem { Label("Network", systemImage: "network") }
                .accessibilityIdentifier("settings-tab-network")
            EnvironmentSettingsTab()
                .tabItem { Label("Environment", systemImage: "terminal") }
                .accessibilityIdentifier("settings-tab-environment")
            ThemeSettingsTab()
                .tabItem { Label("Theme", systemImage: "paintpalette") }
                .accessibilityIdentifier("settings-tab-theme")
        }
        .frame(width: 520, height: 470)
        .onAppear { git.load() }
    }
}

/// Save and Revert for the settings kept in `~/.gitconfig` (author, SSL), shown on every tab that edits them.
struct GitSettingsSaveBar: View {
    let git: GitSettingsModel

    var body: some View {
        Section {
            HStack {
                if let message = git.message {
                    Text(message).foregroundStyle(git.isError ? .red : .secondary)
                }
                Spacer()
                Button("Revert") { git.load() }.disabled(!git.hasChanges)
                Button("Save") { git.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!git.hasChanges)
                    .accessibilityIdentifier("settings-save")
            }
        } footer: {
            Text("Stored in your global git configuration, so the terminal uses the same values.")
        }
    }
}

/// Who the commits are from, and the logins for git servers.
struct AccountSettingsTab: View {
    @Bindable var git: GitSettingsModel

    var body: some View {
        Form {
            Section("Commit author") {
                TextField("Name", text: $git.name)
                    .accessibilityIdentifier("settings-name")
                TextField("Email", text: $git.email)
                    .accessibilityIdentifier("settings-email")
            }
            GitSettingsSaveBar(git: git)
            GitAccountsSection()
        }
        .formStyle(.grouped)
    }
}

/// How git talks to servers.
struct NetworkSettingsTab: View {
    @Bindable var git: GitSettingsModel

    var body: some View {
        Form {
            Section("Connection") {
                Toggle("Verify SSL certificates", isOn: $git.verifiesSSL)
                    .accessibilityIdentifier("settings-ssl")
                if !git.verifiesSSL {
                    Label("https remotes are no longer checked. Turn this off only for a server you trust.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            GitSettingsSaveBar(git: git)
        }
        .formStyle(.grouped)
    }
}

/// What git sees from the terminal.
struct EnvironmentSettingsTab: View {
    var body: some View {
        Form { TerminalEnvironmentSection() }
            .formStyle(.grouped)
    }
}

/// Light, dark or follow the system.
struct ThemeSettingsTab: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearanceRaw = AppearanceSetting.system.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dark mode", isOn: darkMode)
                    .disabled(appearance == .system)
                    .accessibilityIdentifier("settings-dark")
                Toggle("Follow system appearance", isOn: followsSystem)
                    .accessibilityIdentifier("settings-system-appearance")
            }
        }
        .formStyle(.grouped)
    }

    private var appearance: AppearanceSetting { AppearanceSetting(storedValue: appearanceRaw) }

    private var darkMode: Binding<Bool> {
        Binding(
            get: { appearance == .dark },
            set: { appearanceRaw = ($0 ? AppearanceSetting.dark : .light).rawValue }
        )
    }

    private var followsSystem: Binding<Bool> {
        Binding(
            get: { appearance == .system },
            set: { appearanceRaw = ($0 ? AppearanceSetting.system : currentSystemChoice).rawValue }
        )
    }

    /// Turning "follow system" off keeps what the screen shows now.
    private var currentSystemChoice: AppearanceSetting {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}

#Preview("Light") {
    SettingsView().preferredColorScheme(.light)
}

#Preview("Dark") {
    SettingsView().preferredColorScheme(.dark)
}
