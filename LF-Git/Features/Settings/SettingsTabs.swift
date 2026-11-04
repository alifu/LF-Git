import SwiftUI

/// Behaviour of the app itself.
struct GeneralSettingsTab: View {
    @AppStorage(AppModel.reopenLastKey) private var reopensLastRepository = true

    var body: some View {
        SettingsPage {
            SettingsCard("Startup", description: "What LF-Git does when it opens.") {
                Toggle("Reopen the last repository when the app starts", isOn: $reopensLastRepository)
                    .accessibilityIdentifier("settings-reopen-last")
            }
        }
    }
}

/// Who the commits are from, and the logins for git servers.
struct AccountSettingsTab: View {
    @Bindable var git: GitSettingsModel

    var body: some View {
        SettingsPage {
            SettingsCard("Commit author", description: "The name and email on the commits you make.") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $git.name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings-name")
                    TextField("Email", text: $git.email)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings-email")
                }
            }
            GitSettingsSaveBar(git: git)
            SettingsCard("Git server accounts",
                         description: "For a server that signs in with a personal access token (GitHub, GitLab, Bitbucket) or your company (LDAP) account. Enter the token as the password. It is kept by git's credential helper (the macOS keychain), never by this app, so fetch, pull and push work without a prompt. A login you already made in the terminal works without adding it here.") {
                GitAccountsSection()
            }
        }
    }
}

/// How git talks to servers.
struct NetworkSettingsTab: View {
    @Bindable var git: GitSettingsModel

    var body: some View {
        SettingsPage {
            SettingsCard("Connection", description: "Whether git checks the certificates of https servers.") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Verify SSL certificates", isOn: $git.verifiesSSL)
                        .accessibilityIdentifier("settings-ssl")
                    if !git.verifiesSSL {
                        Label("https remotes are no longer checked. Turn this off only for a server you trust.",
                              systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }
            GitSettingsSaveBar(git: git)
        }
    }
}

/// What git sees from the terminal.
struct EnvironmentSettingsTab: View {
    var body: some View {
        SettingsPage {
            TerminalEnvironmentSection()
        }
    }
}

/// Light, dark or follow the system, and the accent color.
struct ThemeSettingsTab: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearanceRaw = AppearanceSetting.system.rawValue
    @AppStorage(AccentSetting.storageKey) private var accentRaw = LFAccentChoice.teal.rawValue

    var body: some View {
        SettingsPage {
            SettingsCard("Appearance", description: "Light, dark, or follow the system.") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Dark mode", isOn: darkMode)
                        .disabled(appearance == .system)
                        .accessibilityIdentifier("settings-dark")
                    Toggle("Follow system appearance", isOn: followsSystem)
                        .accessibilityIdentifier("settings-system-appearance")
                }
            }
            SettingsCard("Accent color",
                         description: "Used for buttons, the selected section and row, and links. Teal is the default.") {
                HStack(spacing: 14) {
                    ForEach(LFAccentChoice.allCases, id: \.self) { choice in
                        AccentSwatch(choice: choice, isSelected: AccentSetting.choice(storedValue: accentRaw) == choice) {
                            accentRaw = choice.rawValue
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
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
