import LFKit
import SwiftUI

/// Shown until a repository is open.
struct WelcomeView: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("LF-Git", systemImage: "arrow.triangle.merge")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.theme(.accentText))
                Text("Resolve conflicts in files of any size, including Xcode project files.")
                    .foregroundStyle(.theme(.textSubtle))
            }
            ConflictPreview()
            HStack(spacing: 16) {
                LegendItem(title: "Current", token: .minimapCurrent)
                LegendItem(title: "Incoming", token: .minimapIncoming)
                LegendItem(title: "Unresolved", token: .minimapUnresolved)
                Spacer()
                Button("Open Repository…", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("open-repository")
            }
            Spacer(minLength: 0)
            Text("Engine \(LFKitInfo.version)  ·  Tip: `lfgit open` in a repository opens it here.")
                .font(.caption)
                .foregroundStyle(.theme(.textSubtle))
        }
        .padding(24)
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.theme(.background))
    }
}

struct LegendItem: View {
    let title: String
    let token: LFThemeToken

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.theme(token)).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.theme(.text))
        }
        .font(.callout)
    }
}

#Preview {
    WelcomeView(onOpen: {})
}
