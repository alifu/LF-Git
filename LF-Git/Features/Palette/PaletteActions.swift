import LFKit
import SwiftUI

/// One entry of the command palette.
struct PaletteAction: Identifiable {
    let id: String
    let title: String
    var symbol = "command"
    var hint: String?
    var isEnabled = true
    let perform: () -> Void
}

extension RepositoryModel {
    /// Every action that needs no further choice. The palette searches this list.
    func paletteActions(app: AppModel) -> [PaletteAction] {
        let idle = !isBusy && operation == nil
        var actions: [PaletteAction] = RepositorySection.allCases.enumerated().map { index, section in
            PaletteAction(id: "go-\(section.rawValue)", title: "Go to \(section.rawValue)", symbol: section.symbol,
                          hint: index < 9 ? "⌃\(index + 1)" : "⌃0") { [self] in self.section = section }
        }
        func git(_ id: String, _ title: String, symbol: String, hint: String? = nil, enabled: Bool = true,
                 _ work: @escaping () async throws -> Void) {
            actions.append(PaletteAction(id: id, title: title, symbol: symbol, hint: hint, isEnabled: enabled) { app.run(work) })
        }
        git("fetch", "Fetch", symbol: "arrow.triangle.2.circlepath", hint: "⌥⌘F", enabled: idle) { try await self.fetch() }
        git("pull", "Pull (fast-forward only)", symbol: "arrow.down", hint: "⌥⌘L", enabled: idle) { try await self.pull(.fastForwardOnly) }
        git("pull-merge", "Pull and Merge", symbol: "arrow.down", enabled: idle) { try await self.pull(.merge) }
        git("pull-rebase", "Pull and Rebase", symbol: "arrow.down", enabled: idle) { try await self.pull(.rebase) }
        git("push", "Push", symbol: "arrow.up", hint: "⌥⌘P", enabled: idle) { try await self.push() }
        actions.append(PaletteAction(id: "force-push", title: "Force Push (with lease)…", symbol: "arrow.up.circle", isEnabled: idle) { [self] in
            confirm(PendingConfirmation(title: "Force push \(status.branch ?? "this branch")?",
                                        message: "The remote branch is overwritten, unless somebody else pushed to it since your last fetch.",
                                        confirmTitle: "Force Push") { app.run { try await self.push(force: true) } })
        })
        git("cancel", "Cancel the Running Action", symbol: "xmark.circle", enabled: isCancellable) { self.cancelBusy() }
        git("stage-all", "Stage All Changes", symbol: "plus.circle", enabled: !status.unstaged.isEmpty) { try await self.changes.stageAll() }
        git("unstage-all", "Unstage All Changes", symbol: "minus.circle", enabled: !status.staged.isEmpty) { try await self.changes.unstageAll() }
        actions.append(PaletteAction(id: "discard-all", title: "Discard All Changes…", symbol: "trash", isEnabled: !status.isClean) { [self] in
            confirm(PendingConfirmation(title: "Discard every change?",
                                        message: "Edits to tracked files are reverted and untracked files are deleted. This cannot be undone.",
                                        confirmTitle: "Discard Everything") {
                app.run { try await self.perform("Discarding…") { client, _ in try client.discardEverything() } }
            })
        })
        git("undo", "Undo the Last Git Move (Reflog)", symbol: "arrow.uturn.backward", hint: "⌥⌘Z", enabled: idle) { try await self.undoHeadMove() }
        git("paste", "Paste Copied Commits (Cherry-Pick)", symbol: "doc.on.clipboard", enabled: idle && !copiedCommits.isEmpty) {
            try await self.pasteCopiedCommits()
        }
        git("previous-branch", "Switch to the Previous Branch", symbol: "arrow.uturn.backward", enabled: idle) {
            try await self.perform("Switching…") { client, _ in try client.switchPrevious() }
        }
        git("reload", "Reload", symbol: "arrow.clockwise", hint: "⌘R") { await self.refresh(reloadDiffs: true) }
        git("bisect-reset", "Stop Bisecting", symbol: "stop.circle", enabled: isBisecting) { try await self.resetBisect() }
        actions.append(PaletteAction(id: "command-log", title: "Show or Hide the Log Panel", symbol: "terminal", hint: "⇧⌘L") { [self] in showsLogPanel.toggle() })
        actions.append(PaletteAction(id: "help", title: "Keyboard Shortcuts", symbol: "keyboard", hint: "⌘/") { [self] in showsHelp = true })
        actions += customCommandActions(app: app)
        return actions
    }

    private func customCommandActions(app: AppModel) -> [PaletteAction] {
        guard let config = try? CustomCommandConfig.load() else { return [] }
        return config.customCommands.map { command in
            PaletteAction(id: "custom-\(command.name)", title: command.name, symbol: "terminal", hint: "custom") { [self] in
                app.run {
                    let box = ResultBox<CustomCommandResult>()
                    let branch = self.status.branch
                    try await self.perform("Running \(command.name)…", cancellable: true) { client, token in
                        box.value = try client.run(command, cancellation: token, branch: branch)
                    }
                    if let result = box.value, result.status != 0 || !result.output.isEmpty {
                        app.errorMessage = (result.status == 0 ? "" : "Exit status \(result.status)\n\n") + result.output
                    }
                }
            }
        }
    }
}

/// ⌘K: type to find an action.
struct CommandPaletteView: View {
    let repository: RepositoryModel
    let app: AppModel
    @State private var query = ""
    @State private var highlighted: String?
    @FocusState private var focused: Bool

    private var matches: [PaletteAction] {
        let all = repository.paletteActions(app: app)
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return all }
        return all.filter { action in words.allSatisfy { action.title.lowercased().contains($0) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Type a command", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($focused)
                .onSubmit { run(matches.first { $0.isEnabled }) }
                .accessibilityIdentifier("palette-field")
            Divider()
            List(matches, selection: $highlighted) { action in
                HStack {
                    Image(systemName: action.symbol).frame(width: 20).foregroundStyle(.theme(.accentText))
                    Text(action.title)
                    Spacer()
                    if let hint = action.hint { Text(hint).font(.caption).foregroundStyle(.theme(.textSubtle)) }
                }
                .opacity(action.isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onTapGesture { run(action) }
                .tag(action.id)
                .accessibilityIdentifier("palette-\(action.id)")
            }
            .listStyle(.plain)
        }
        .frame(width: 520, height: 420)
        .onAppear { focused = true }
        .onExitCommand { repository.showsPalette = false }
    }

    private func run(_ action: PaletteAction?) {
        guard let action, action.isEnabled else { return }
        repository.showsPalette = false
        action.perform()
    }
}

/// The shortcuts, grouped like the menus.
struct KeyboardHelpView: View {
    let repository: RepositoryModel

    private static let groups: [(String, [(String, String)])] = [
        ("Everywhere", [("⌘K", "Command palette"), ("⌘/", "This list"), ("⇧⌘L", "Log panel"), ("⌃1 … ⌃0", "Go to a section"),
                        ("⌘R", "Reload"), ("⌘O", "Open repository"), ("⌥⌘Z", "Undo the last git move (reflog)")]),
        ("Remote", [("⌥⌘F", "Fetch"), ("⌥⌘L", "Pull"), ("⌥⌘P", "Push"), ("⎋", "Cancel is in the toolbar while a command runs")]),
        ("Changes", [("⌘↩", "Commit"), ("Click ± on a hunk", "Stage or unstage a hunk"), ("Select lines, then button", "Stage or discard lines")]),
        ("Conflicts", [("⌘1 … ⌘4", "Accept current / incoming / both / base"), ("⌥⌘↓ / ⌥⌘↑", "Next / previous conflict"), ("⌘S", "Save")]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(.headline)
                Spacer()
                Button("Done") { repository.showsHelp = false }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            List {
                ForEach(Self.groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1, id: \.0) { item in
                            HStack {
                                Text(item.0).font(.body.monospaced()).frame(width: 190, alignment: .leading)
                                Text(item.1).foregroundStyle(.theme(.textSubtle))
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 560, height: 440)
    }
}

#if DEBUG
#Preview("Command palette") {
    PreviewRepository(width: 560, height: 420) { repository, app in
        CommandPaletteView(repository: repository, app: app)
    }
}
#endif

#if DEBUG
#Preview("Keyboard help") {
    PreviewRepository(width: 520, height: 520) { repository, app in
        KeyboardHelpView(repository: repository)
    }
}
#endif
