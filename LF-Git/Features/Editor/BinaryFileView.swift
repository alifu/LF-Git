import AppKit
import LFKit
import SwiftUI

/// Binary files cannot be merged line by line: show both versions and keep one.
struct BinaryFileView: View {
    let repository: RepositoryModel
    let file: ConflictedFile
    let app: AppModel
    @State private var current: NSImage?
    @State private var incoming: NSImage?

    var body: some View {
        VStack(spacing: 20) {
            Label("\(file.name) is a binary file", systemImage: "photo")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.theme(.text))
            Text("It cannot be merged line by line. Keep one version.")
                .foregroundStyle(.theme(.textSubtle))
            HStack(alignment: .top, spacing: 24) {
                side("Current", image: current, header: .conflictCurrentHeader, side: .ours)
                side("Incoming", image: incoming, header: .conflictIncomingHeader, side: .theirs)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.theme(.background))
        .task(id: file.id) {
            current = await Self.image(stage: 2, path: file.path, root: repository.root)
            incoming = await Self.image(stage: 3, path: file.path, root: repository.root)
        }
    }

    private func side(_ title: String, image: NSImage?, header: LFThemeToken, side: Git.Side) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(6).background(.theme(header))
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "doc").font(.largeTitle).foregroundStyle(.theme(.textSubtle))
                }
            }
            .frame(width: 220, height: 160)
            Button("Use \(title)") {
                Task {
                    do { try await repository.takeSide(side, of: file.path) } catch { app.report(error) }
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("use-\(title.lowercased())")
        }
        .frame(width: 240)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 8).stroke(.theme(.border)))
    }

    /// The version of the file in index stage 2 (ours) or 3 (theirs), if it is an image.
    @concurrent
    nonisolated private static func image(stage: Int, path: String, root: URL) async -> NSImage? {
        guard let result = try? Git(directory: root).run(["show", ":\(stage):\(path)"]) else { return nil }
        return NSImage(data: result.stdout)
    }
}
