import SwiftUI

struct SettingsView: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearanceRaw = AppearanceSetting.system.rawValue
    @State private var git = GitSettingsModel()

    var body: some View {
        Form {
            Section("Commit author") {
                TextField("Name", text: $git.name)
                    .accessibilityIdentifier("settings-name")
                TextField("Email", text: $git.email)
                    .accessibilityIdentifier("settings-email")
            }
            Section("Network") {
                Toggle("Verify SSL certificates", isOn: $git.verifiesSSL)
                    .accessibilityIdentifier("settings-ssl")
                if !git.verifiesSSL {
                    Label("https remotes are no longer checked. Turn this off only for a server you trust.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
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
            GitAccountsSection()
            TerminalEnvironmentSection()
            Section("Appearance") {
                Toggle("Dark mode", isOn: darkMode)
                    .disabled(appearance == .system)
                    .accessibilityIdentifier("settings-dark")
                Toggle("Follow system appearance", isOn: followsSystem)
                    .accessibilityIdentifier("settings-system-appearance")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { git.load() }
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
