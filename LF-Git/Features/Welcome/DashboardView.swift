import AppKit
import LFKit
import SwiftUI

/// Shown until a repository is open: open or clone one, pick up where you left off, see which repositories need you.
struct DashboardView: View {
    let app: AppModel
    @State private var summaries = RepositorySummaries()
    @State private var filter = ""

    private static let searchThreshold = 8

    private var lastOpened: String? { app.recentRepositories.first }
    private var earlier: [String] {
        let rest = Array(app.recentRepositories.dropFirst()).filter { !needingAttention.contains($0) }
        let text = filter.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? rest : rest.filter { $0.localizedCaseInsensitiveContains(text) }
    }
    private var needingAttention: [String] {
        // The last-opened card already shows its own chips.
        app.recentRepositories.dropFirst().filter { summaries.summary(for: $0)?.needsAttention == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if let note = app.restoreNote {
                Label(note, systemImage: "info.circle")
                    .foregroundStyle(.theme(.textSubtle))
                    .accessibilityIdentifier("dashboard-restore-note")
            }
            actions
            if let lastOpened { lastOpenedCard(lastOpened) }
            // Only the recent list scrolls; everything else keeps its place.
            HStack(alignment: .top, spacing: 24) {
                recents
                preview.frame(width: 300)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Text("Engine \(LFKitInfo.version)  ·  Tip: `lfgit open` in a repository opens it here.")
                .font(.caption)
                .foregroundStyle(.theme(.textSubtle))
        }
        .padding(28)
        .frame(maxWidth: 900, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.theme(.background))
        .task(id: app.recentRepositories) { await summaries.refresh(app.recentRepositories) }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                Text("LF-Git")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.theme(.accentText))
            }
            Text("Resolve conflicts in files of any size, including Xcode project files.")
                .foregroundStyle(.theme(.textSubtle))
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            ActionCard(title: "Open Repository…", detail: "Choose a folder on this Mac", symbol: "folder", shortcut: "⌘O",
                       identifier: "open-repository") { app.chooseRepository() }
            ActionCard(title: "Clone Repository…", detail: "From a web address, public or private", symbol: "arrow.down.circle",
                       shortcut: "⇧⌘O", identifier: "clone-repository") { app.showsClone = true }
        }
    }

    private func lastOpenedCard(_ path: String) -> some View {
        DashboardSection("Last opened") {
            RecentRepositoryRow(path: path, summary: summaries.summary(for: path), app: app, prominent: true)
        }
        .accessibilityIdentifier("dashboard-last-opened")
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.theme(.textSubtle))
                Spacer()
                if !app.recentRepositories.isEmpty {
                    Button("Clear") { filter = ""; app.clearRecentRepositories() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .help("Forget the recent repositories. The repositories themselves are not touched.")
                        .accessibilityIdentifier("dashboard-clear-recents")
                }
            }
            if app.recentRepositories.count > Self.searchThreshold {
                TextField("Search recent repositories", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("dashboard-search")
            }
            if earlier.isEmpty && needingAttention.isEmpty {
                Text(app.recentRepositories.count > 1 ? "Nothing matches \"\(filter)\"." : "Repositories you open or clone show up here.")
                    .foregroundStyle(.theme(.textSubtle))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !needingAttention.isEmpty {
                        Text("Needs attention")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.theme(.danger))
                            .accessibilityIdentifier("dashboard-attention")
                        ForEach(needingAttention, id: \.self) { path in
                            RecentRepositoryRow(path: path, summary: summaries.summary(for: path), app: app)
                        }
                    }
                    ForEach(earlier, id: \.self) { path in
                        RecentRepositoryRow(path: path, summary: summaries.summary(for: path), app: app)
                    }
                }
            }
            .accessibilityIdentifier("dashboard-recents")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var preview: some View {
        DashboardSection("Preview") {
            ConflictPreview()
            HStack(spacing: 16) {
                LegendItem(title: "Current", token: .minimapCurrent)
                LegendItem(title: "Incoming", token: .minimapIncoming)
                LegendItem(title: "Unresolved", token: .minimapUnresolved)
            }
        }
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.theme(.textSubtle))
            content
        }
    }
}

private struct ActionCard: View {
    let title: String
    let detail: String
    let symbol: String
    let shortcut: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.theme(.accentText))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.theme(.textSubtle))
                }
                Spacer(minLength: 4)
                Text(shortcut).font(.caption.monospaced()).foregroundStyle(.theme(.textSubtle))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.theme(.surfaceRaised), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.theme(.border)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
    DashboardView(app: AppModel())
}
