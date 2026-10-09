import LFKit
import SwiftUI

/// Placeholder home screen until the conflict editor lands (Phase 4).
struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            ConflictPreview()
            legend
            Spacer(minLength: 0)
            Text("Engine \(LFKitInfo.version)")
                .font(.caption)
                .foregroundStyle(.theme(.textSubtle))
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 360, alignment: .topLeading)
        .background(.theme(.background))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("LF-Git", systemImage: "arrow.triangle.merge")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.theme(.accentText))
            Text("Resolve conflicts in files of any size.")
                .foregroundStyle(.theme(.textSubtle))
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            LegendItem(title: "Current", token: .minimapCurrent)
            LegendItem(title: "Incoming", token: .minimapIncoming)
            LegendItem(title: "Unresolved", token: .minimapUnresolved)
            Spacer()
            Button("Open Repository…") {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
                .help("Available once the conflict editor is implemented")
        }
    }
}

private struct LegendItem: View {
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

#Preview("Light") {
    ContentView().preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView().preferredColorScheme(.dark)
}
