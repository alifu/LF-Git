import SwiftUI

/// The settings window: one tab per topic.
struct SettingsView: View {
    @State private var git = GitSettingsModel()

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .accessibilityIdentifier("settings-tab-general")
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

/// Behaviour of the app itself.
struct GeneralSettingsTab: View {
    @AppStorage(AppModel.reopenLastKey) private var reopensLastRepository = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Reopen the last repository when the app starts", isOn: $reopensLastRepository)
                    .accessibilityIdentifier("settings-reopen-last")
            }
        }
        .formStyle(.grouped)
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

/// Light, dark or follow the system, and the accent color.
struct ThemeSettingsTab: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearanceRaw = AppearanceSetting.system.rawValue
    @AppStorage(AccentSetting.storageKey) private var accentRaw = LFAccentChoice.green.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dark mode", isOn: darkMode)
                    .disabled(appearance == .system)
                    .accessibilityIdentifier("settings-dark")
                Toggle("Follow system appearance", isOn: followsSystem)
                    .accessibilityIdentifier("settings-system-appearance")
            }
            Section {
                HStack(spacing: 14) {
                    ForEach(LFAccentChoice.allCases, id: \.self) { choice in
                        AccentSwatch(choice: choice, isSelected: AccentSetting.choice(storedValue: accentRaw) == choice) {
                            accentRaw = choice.rawValue
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accent color")
            } footer: {
                Text("Used for buttons, the selected section and row, and links. Green is the default.")
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

/// One round color sample; the chosen one has a ring and a check.
private struct AccentSwatch: View {
    let choice: LFAccentChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color(LFThemeToken.accent.assetName(for: choice), bundle: .main))
                    .frame(width: 26, height: 26)
                    .overlay { if isSelected { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                    .padding(3)
                    .overlay(Circle().stroke(.primary.opacity(isSelected ? 0.7 : 0), lineWidth: 2))
                Text(choice.rawValue.capitalized).font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.rawValue.capitalized)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings-accent-\(choice.rawValue)")
    }
}

#Preview("Light") {
    SettingsView().preferredColorScheme(.light)
}

#Preview("Dark") {
    SettingsView().preferredColorScheme(.dark)
}
