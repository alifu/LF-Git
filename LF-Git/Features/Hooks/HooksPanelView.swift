import SwiftUI

/// Shows what the hooks of a push or commit print, live, instead of leaving them to terminal windows.
struct HooksPanelView: View {
    let repository: RepositoryModel
    @State private var selectedID: Int?

    private static let height = 220.0
    private static let bottomAnchor = "hook-output-bottom"

    private var runs: [HookRun] { repository.hooks.runs }
    private var shown: HookRun? {
        runs.first { $0.id == selectedID } ?? runs.last
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            output
        }
        .frame(height: Self.height)
        .background(.theme(.surfaceRaised))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hook-output")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Hooks", systemImage: "checkmark.shield").font(.headline)
            if let run = shown { statusChip(run) }
            Spacer()
            if runs.count > 1 {
                Picker("Run", selection: Binding(get: { shown?.id ?? 0 }, set: { selectedID = $0 })) {
                    ForEach(runs.reversed()) { Text("\($0.title) \($0.started.formatted(date: .omitted, time: .standard))").tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            Button { if let run = shown { Clipboard.copy(run.text) } } label: { Image(systemName: "doc.on.doc") }
                .help("Copy the output")
                .disabled(shown?.text.isEmpty ?? true)
            Button { repository.hooks.clear() } label: { Image(systemName: "trash") }
                .help("Clear finished runs")
                .disabled(runs.isEmpty)
            Button { repository.showsHooksPanel = false } label: { Image(systemName: "xmark") }
                .help("Hide the hook output")
                .accessibilityIdentifier("hook-output-close")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func statusChip(_ run: HookRun) -> some View {
        switch run.state {
        case .running:
            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("\(run.title) running…") }.font(.caption)
        case .passed:
            Label("\(run.title) passed" + durationText(run), systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let reason):
            Label("\(run.title) failed" + durationText(run), systemImage: "xmark.octagon.fill")
                .font(.caption).foregroundStyle(.red).help(reason)
        }
    }

    private func durationText(_ run: HookRun) -> String {
        run.duration.map { String(format: " in %.1f s", $0) } ?? ""
    }

    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(outputText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(shown?.text.isEmpty ?? true ? .theme(.textSubtle) : .theme(.text))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(12)
            }
            .onChange(of: shown?.text.count) { proxy.scrollTo(Self.bottomAnchor) }
        }
    }

    private var outputText: String {
        guard let run = shown else { return "No hook has run yet." }
        let suffix = run.isTruncated ? "\n… output truncated" : ""
        if run.text.isEmpty { return run.state == .running ? "Waiting for output…" : "The hooks printed nothing." }
        return run.text + suffix
    }
}
