import AppKit
import LFKit
import SwiftUI

/// Where one side of a binary diff is read from.
nonisolated enum BinarySource: Sendable, Equatable {
    /// `git show <revision>:<path>`; an empty revision means the index (`:<path>`).
    case blob(revision: String, path: String)
    /// A file in the work tree.
    case workTree(path: String)
}

/// The two sides of a changed binary file. A nil side did not exist (the file was added or deleted).
nonisolated struct BinarySides: Sendable, Equatable {
    let root: URL
    let before: BinarySource?
    let after: BinarySource?

    /// The file's name, which decides the icon shown for a type that cannot be previewed.
    var fileName: String {
        let path: String? = switch after ?? before {
        case .blob(_, let path), .workTree(let path): path
        case nil: nil
        }
        return ((path ?? "") as NSString).lastPathComponent
    }

    /// The sides of the work-tree change to `path`: HEAD → index when staged, index → work tree when not.
    static func workingTree(root: URL, path: String, staged: Bool, isNew: Bool) -> BinarySides {
        if staged {
            return BinarySides(root: root, before: isNew ? nil : .blob(revision: "HEAD", path: path),
                               after: .blob(revision: "", path: path))
        }
        return BinarySides(root: root, before: isNew ? nil : .blob(revision: "", path: path), after: .workTree(path: path))
    }

    /// The sides of one file between two revisions (a commit and its first parent, or two picked commits).
    static func revisions(root: URL, from: String?, to: String, path: String, originalPath: String?) -> BinarySides {
        BinarySides(root: root, before: from.map { .blob(revision: $0, path: originalPath ?? path) },
                    after: .blob(revision: to, path: path))
    }
}

/// A changed binary file: the version before and after, side by side, or swiped when both are images.
struct BinaryDiffView: View {
    private enum Layout: String, CaseIterable, Identifiable {
        case sideBySide = "Side by Side"
        case swipe = "Swipe"
        var id: String { rawValue }
    }

    let sides: BinarySides
    @State private var before: BinaryVersion?
    @State private var after: BinaryVersion?
    @State private var layout = Layout.sideBySide
    @State private var swipe = 0.5

    private var images: (NSImage, NSImage)? {
        guard let a = before?.image, let b = after?.image else { return nil }
        return (a, b)
    }

    var body: some View {
        VStack(spacing: 10) {
            if images != nil {
                Picker("Compare", selection: $layout) {
                    ForEach(Layout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .accessibilityIdentifier("binary-diff-layout")
            }
            if let before, let after {
                if layout == .swipe, let images {
                    swipeView(images)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        side("Before", version: before, missing: "Did not exist")
                        side("After", version: after, missing: "Deleted")
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("binary-diff")
        .task(id: sides) {
            before = nil
            after = nil
            layout = .sideBySide
            async let loadedBefore = Self.load(sides.before, root: sides.root)
            async let loadedAfter = Self.load(sides.after, root: sides.root)
            (before, after) = await (loadedBefore, loadedAfter)
        }
    }

    private func swipeView(_ images: (NSImage, NSImage)) -> some View {
        VStack(spacing: 8) {
            ImageSwipeView(current: images.0, incoming: images.1, fraction: swipe)
                .frame(maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.theme(.border)))
            HStack {
                Text("Before").font(.caption)
                Slider(value: $swipe, in: 0...1).accessibilityIdentifier("binary-diff-swipe")
                Text("After").font(.caption)
            }
            .frame(maxWidth: 420)
        }
    }

    private func side(_ title: String, version: BinaryVersion, missing: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(4).background(.theme(.surfaceRaised))
            BinaryPreview(version: version, fileName: sides.fileName, missingText: missing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(version.kind == .missing ? missing : version.summary)
                .font(.caption)
                .foregroundStyle(.theme(.textSubtle))
        }
        .padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 8).stroke(.theme(.border)))
    }

    /// Reads one side; a side that does not exist (or cannot be read) is shown as missing.
    @concurrent
    nonisolated private static func load(_ source: BinarySource?, root: URL) async -> BinaryVersion {
        guard let source else { return .missing }
        switch source {
        case .blob(let revision, let path):
            let data = try? Git(directory: root).run(["show", "\(revision):\(path)"]).stdout
            return BinaryVersion.classify(data)
        case .workTree(let path):
            return BinaryVersion.classify(try? Data(contentsOf: root.appendingPathComponent(path)))
        }
    }
}
