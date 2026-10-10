import SwiftUI

/// A panel at the bottom of the window that shows what is happening: every git command, each action that
/// started, finished, was cancelled or failed, and reloads after outside edits.
struct LogPanelView: View {
    let repository: RepositoryModel
    @AppStorage("logPanelHeight") private var storedHeight = LogPanelView.defaultHeight
    @State private var filter = LogFilter.all
    @State private var dragStartHeight: Double?

    static let defaultHeight = 200.0
    private static let heightRange = 110.0...520.0

    private var events: [LogEvent] { repository.activity.filter(filter.includes) }
    private var height: Double { min(max(storedHeight, Self.heightRange.lowerBound), Self.heightRange.upperBound) }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            header
            Divider()
            list
        }
        .frame(height: height)
        .background(.theme(.surfaceRaised))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("command-log")
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(.theme(.border))
            .frame(height: 1)
            .overlay {
                Color.clear.frame(height: 8).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = dragStartHeight ?? height
                            dragStartHeight = start
                            storedHeight = min(max(start - drag.translation.height, Self.heightRange.lowerBound), Self.heightRange.upperBound)
                        }
                        .onEnded { _ in dragStartHeight = nil })
            }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Log", systemImage: "terminal").font(.headline)
            Picker("Show", selection: $filter) {
                ForEach(LogFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            .accessibilityIdentifier("log-filter")
            Spacer()
            Text("\(events.count) \(events.count == 1 ? "line" : "lines")")
                .font(.caption).foregroundStyle(.theme(.textSubtle))
            Button { Clipboard.copy(LogEvent.transcript(events)) } label: { Image(systemName: "doc.on.doc") }
                .help("Copy the lines shown")
                .disabled(events.isEmpty)
                .accessibilityIdentifier("log-copy")
            Button { repository.clearActivity() } label: { Image(systemName: "trash") }
                .help("Clear the log")
                .disabled(repository.activity.isEmpty)
                .accessibilityIdentifier("log-clear")
            Button { repository.showsLogPanel = false } label: { Image(systemName: "xmark") }
                .help("Hide the log (⇧⌘L)")
                .accessibilityIdentifier("log-close")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(events) { event in
                LogRow(event: event).id(event.id)
            }
            .listStyle(.plain)
            .onAppear { scrollToEnd(proxy) }
            .onChange(of: events.last?.id) { scrollToEnd(proxy) }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView(repository.activity.isEmpty ? "Nothing has happened yet" : "No lines match",
                                           systemImage: "terminal")
                }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = events.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }
}

private struct LogRow: View {
    let event: LogEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(event.date, format: .dateTime.hour().minute().second())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.theme(.textSubtle))
            Image(systemName: symbol).foregroundStyle(.theme(token)).frame(width: 16)
            Text(event.text)
                .font(.system(size: 12, design: event.kind == .git ? .monospaced : .default))
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 8)
            if let duration = event.duration {
                Text(duration < 1 ? "\(Int(duration * 1000)) ms" : String(format: "%.1f s", duration))
                    .font(.caption).foregroundStyle(.theme(.textSubtle))
            }
        }
        .listRowSeparator(.hidden)
    }

    private var symbol: String {
        switch event.kind {
        case .git: event.succeeded ? "checkmark.circle" : "xmark.circle"
        case .action: "play.circle"
        case .info: "info.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private var token: LFThemeToken {
        switch event.kind {
        case .git: event.succeeded ? .accentText : .danger
        case .action, .info: .textSubtle
        case .error: .danger
        }
    }
}

#if DEBUG
#Preview("Log panel") {
    PreviewRepository(width: 900, height: 260) { repository, _ in
        LogPanelView(repository: repository)
            .task {
                repository.record(.action, "Started: Fetching")
                repository.record(.info, "Files changed outside the app: reloaded")
                repository.record(.error, "Failed: Pushing: git push failed (exit 1): rejected", succeeded: false)
            }
    }
}
#endif
