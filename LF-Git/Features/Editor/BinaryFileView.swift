import AppKit
import LFKit
import SwiftUI

/// Binary files cannot be merged line by line: look at both versions (images side by side or swiped, PDFs
/// scrollable), then keep one, or open them in another app first.
struct BinaryFileView: View {
    private enum Layout: String, CaseIterable, Identifiable {
        case sideBySide = "Side by Side"
        case swipe = "Swipe"
        var id: String { rawValue }
    }

    let repository: RepositoryModel
    let file: ConflictedFile
    let app: AppModel
    @State private var current: BinaryVersion?
    @State private var incoming: BinaryVersion?
    @State private var layout = Layout.sideBySide
    @State private var swipe = 0.5

    private var images: (NSImage, NSImage)? {
        guard let a = current?.image, let b = incoming?.image else { return nil }
        return (a, b)
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            if let current, let incoming {
                if layout == .swipe, let images {
                    swipeView(images)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        side("Current", version: current, header: .conflictCurrentHeader, side: .ours)
                        side("Incoming", version: incoming, header: .conflictIncomingHeader, side: .theirs)
                    }
                }
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.theme(.background))
        .task(id: file.id) {
            current = nil
            incoming = nil
            layout = .sideBySide
            current = await Self.version(stage: 2, path: file.path, root: repository.root)
            incoming = await Self.version(stage: 3, path: file.path, root: repository.root)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Label("\(file.name) is a binary file", systemImage: "photo")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.theme(.text))
            Text("It cannot be merged line by line. Compare the versions and keep one.")
                .foregroundStyle(.theme(.textSubtle))
            if images != nil {
                Picker("Compare", selection: $layout) {
                    ForEach(Layout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .accessibilityIdentifier("binary-layout")
            }
        }
    }

    private func swipeView(_ images: (NSImage, NSImage)) -> some View {
        VStack(spacing: 10) {
            ImageSwipeView(current: images.0, incoming: images.1, fraction: swipe)
                .frame(maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.theme(.border)))
            HStack {
                Text("Current").font(.caption)
                Slider(value: $swipe, in: 0...1).accessibilityIdentifier("binary-swipe")
                Text("Incoming").font(.caption)
            }
            .frame(maxWidth: 420)
            keepButtons
        }
    }

    private var keepButtons: some View {
        HStack(spacing: 12) {
            keepButton("Use Current", side: .ours)
            keepButton("Use Incoming", side: .theirs)
        }
    }

    private func keepButton(_ title: String, side: Git.Side) -> some View {
        Button(title) {
            Task {
                do { try await repository.takeSide(side, of: file.path) } catch { app.report(error) }
            }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier(title.lowercased().replacingOccurrences(of: " ", with: "-"))
    }

    private func side(_ title: String, version: BinaryVersion, header: LFThemeToken, side: Git.Side) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(6).background(.theme(header))
            BinaryPreview(version: version, fileName: file.name)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(version.summary).font(.caption).foregroundStyle(.theme(.textSubtle))
            HStack {
                keepButton("Use \(title)", side: side)
                Button("Open…") { open(version) }
                    .help("Open this version in the default app")
                    .disabled(version.kind == .missing)
                    .accessibilityIdentifier("open-\(title.lowercased())")
            }
        }
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 8).stroke(.theme(.border)))
    }

    /// Writes the version to a temporary folder and opens it, so the real file in the work tree is untouched.
    private func open(_ version: BinaryVersion) {
        guard let data = version.data else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(file.name)
            try data.write(to: url)
            NSWorkspace.shared.open(url)
        } catch {
            app.report(error)
        }
    }

    /// The version of the file in index stage 2 (ours) or 3 (theirs); missing when that side deleted it.
    @concurrent
    nonisolated private static func version(stage: Int, path: String, root: URL) async -> BinaryVersion {
        let data = try? Git(directory: root).run(["show", ":\(stage):\(path)"]).stdout
        return BinaryVersion.classify(data)
    }
}
