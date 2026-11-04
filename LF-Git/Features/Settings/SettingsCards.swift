import SwiftUI

/// Spacing and insets shared by the settings cards and their column.
private enum SettingsMetrics {
    static let inset: CGFloat = 16
    static let pageSpacing: CGFloat = 14
    static let cardSpacing: CGFloat = 12
}

/// The scrolling column of one settings tab: its section cards, one under another.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
                content
            }
            .padding(SettingsMetrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A titled section of a settings tab: a title, one line of description, then the controls.
struct SettingsCard<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    init(_ title: String, description: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.theme(.text))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.theme(.textSubtle))
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(SettingsMetrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lfCard()
    }
}

/// Save and Revert for the settings kept in `~/.gitconfig` (author, SSL), shown on every tab that edits them.
struct GitSettingsSaveBar: View {
    let git: GitSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            Text("Stored in your global git configuration, so the terminal uses the same values.")
                .font(.caption)
                .foregroundStyle(.theme(.textSubtle))
        }
    }
}
