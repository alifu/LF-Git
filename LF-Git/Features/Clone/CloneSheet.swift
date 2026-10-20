import AppKit
import LFKit
import SwiftUI

/// Clone a repository from an address: check it, pick the branch, sign in or wait for the VPN, choose where it goes.
struct CloneSheet: View {
    let app: AppModel
    @State private var model = CloneModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                addressSection
                stateSection
                if model.state == .ready || model.isWorking { branchAndOptions }
                if model.found != nil || model.isWorking { destinationSection }
            }
            .formStyle(.grouped)
            .disabled(model.isWorking)
            Divider()
            footer
        }
        .frame(width: 540, height: 560)
        .onChange(of: model.urlText) { model.urlChanged() }
        .onChange(of: model.state) {
            guard case .done(let destination) = model.state else { return }
            dismiss()
            app.open(destination)
        }
        .onAppear(perform: prefillFromPasteboard)
        .onDisappear { model.close() }
    }

    // MARK: - Sections

    private var addressSection: some View {
        Section("Repository address") {
            TextField("Address", text: $model.urlText, prompt: Text("https://github.com/team/project.git"))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityIdentifier("clone-url")
            if let problem = model.urlProblem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityIdentifier("clone-message")
            }
        }
    }

    @ViewBuilder
    private var stateSection: some View {
        switch model.state {
        case .probing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking \(model.host ?? "the address")…")
            }
            .accessibilityIdentifier("clone-checking")
        case .waitingForNetwork:
            Section {
                HStack(alignment: .top, spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Can't reach \(model.host ?? "the server")").font(.headline)
                        Text("If it needs a VPN, connect to it. I'll keep trying and carry on as soon as it answers.")
                            .foregroundStyle(.theme(.textSubtle))
                    }
                }
                HStack {
                    Button("Stop Waiting") { model.stopWaiting() }
                        .accessibilityIdentifier("clone-stop-waiting")
                    Spacer()
                    Button("Retry Now") { model.retryNow() }
                        .accessibilityIdentifier("clone-retry-now")
                }
            }
            .accessibilityIdentifier("clone-waiting")
        case .needsLogin:
            CloneCredentialForm(model: model)
        default:
            EmptyView()
        }
    }

    private var branchAndOptions: some View {
        Section("Branch") {
            if let found = model.found, !found.branches.isEmpty {
                BranchChoice(branches: found.branches, selection: $model.selectedBranch)
            } else {
                Text("The repository is empty: there is no branch to check out yet.")
                    .foregroundStyle(.theme(.textSubtle))
            }
            Toggle("Download every branch", isOn: $model.includesAllBranches)
                .accessibilityIdentifier("clone-all-branches")
            Toggle("Only the latest commit (shallow)", isOn: $model.shallow)
                .accessibilityIdentifier("clone-shallow")
            Toggle("Include submodules", isOn: $model.recurseSubmodules)
                .accessibilityIdentifier("clone-submodules")
        }
    }

    private var destinationSection: some View {
        Section("Where to put it") {
            HStack {
                Text(model.parent?.path ?? "Choose a folder")
                    .foregroundStyle(model.parent == nil ? Color.theme(.textSubtle) : Color.theme(.text))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .accessibilityIdentifier("clone-parent")
                Spacer()
                Button("Choose…", action: chooseParent)
                    .accessibilityIdentifier("clone-choose-folder")
            }
            TextField("Folder name", text: Binding(get: { model.folderName }, set: { model.editFolderName($0) }))
                .accessibilityIdentifier("clone-folder-name")
            if let problem = model.destinationProblem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var footer: some View {
        HStack {
            if case .cloning(let progress) = model.state {
                ProgressView(value: Double(progress?.percent ?? 0), total: 100)
                    .frame(width: 180)
                Text(progress.map { "\($0.phase) \($0.percent)%" } ?? "Starting…")
                    .font(.caption)
                    .foregroundStyle(.theme(.textSubtle))
                    .accessibilityIdentifier("clone-progress")
            }
            Spacer()
            if model.isWorking {
                Button("Stop") { model.cancel() }
                    .accessibilityIdentifier("clone-stop")
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("clone-cancel")
                Button("Clone") { model.clone() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canClone)
                    .accessibilityIdentifier("clone-button")
            }
        }
        .padding(12)
    }

    // MARK: - Actions

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that will contain the repository."
        if panel.runModal() == .OK, let url = panel.url { model.chooseParent(url) }
    }

    /// A copied repository address is the most likely thing to clone.
    private func prefillFromPasteboard() {
        guard model.urlText.isEmpty, let text = NSPasteboard.general.string(forType: .string),
              (try? RemoteURL.parse(text)) != nil else { return }
        model.urlText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A menu of the branches, with a filter box once the list is long.
private struct BranchChoice: View {
    let branches: [String]
    @Binding var selection: String?
    @State private var filter = ""
    private static let longList = 15

    private var shown: [String] {
        let text = filter.trimmingCharacters(in: .whitespaces)
        let matching = text.isEmpty ? branches : branches.filter { $0.localizedCaseInsensitiveContains(text) }
        // The chosen branch stays listed, or the picker would show nothing while filtering.
        return selection.map { chosen in matching.contains(chosen) ? matching : [chosen] + matching } ?? matching
    }

    var body: some View {
        if branches.count > Self.longList {
            TextField("Filter \(branches.count) branches", text: $filter)
                .accessibilityIdentifier("clone-branch-filter")
        }
        Picker("Check out", selection: $selection) {
            ForEach(shown, id: \.self) { Text($0).tag(Optional($0)) }
        }
        .accessibilityIdentifier("clone-branch")
    }
}

#Preview("Clone") {
    CloneSheet(app: AppModel())
}
