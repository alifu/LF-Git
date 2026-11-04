import SwiftUI

/// Settings card: use the terminal's PATH, SSH agent and tokens for git.
struct TerminalEnvironmentSection: View {
    @State private var environment = TerminalEnvironment.shared

    var body: some View {
        SettingsCard("Terminal environment",
                     description: "An app started from the Dock does not see what your shell exports. With this on, git here uses your terminal's PATH (for gh or git-credential-manager), SSH agent and tokens such as GITHUB_TOKEN, so what works in the terminal works here. Only those settings are taken, and values are never shown or logged.") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use my terminal's environment", isOn: Binding(
                    get: { environment.isEnabled }, set: { environment.setEnabled($0) }))
                    .accessibilityIdentifier("settings-terminal-environment")
                LabeledContent("git") {
                    Text(environment.gitPath.map { "\($0) · \(environment.gitVersion ?? "")" } ?? "not found")
                        .font(.callout.monospaced()).foregroundStyle(.theme(.textSubtle)).textSelection(.enabled)
                }
                if environment.isEnabled {
                    LabeledContent("Imported") {
                        Text(environment.isLoading ? "reading your shell…"
                             : environment.importedNames.isEmpty ? "nothing (the shell printed no PATH, agent or tokens)"
                             : environment.importedNames.joined(separator: ", "))
                            .font(.callout).foregroundStyle(.theme(.textSubtle)).textSelection(.enabled)
                    }
                }
                HStack {
                    Spacer()
                    Button("Reload") { Task { await environment.reload() } }.disabled(environment.isLoading)
                }
            }
        }
        .onAppear { if environment.gitPath == nil { Task { await environment.reload() } } }
    }
}

#Preview("Terminal environment") {
    SettingsPage { TerminalEnvironmentSection() }
        .frame(width: 580, height: 400)
}
