#if DEBUG
import Foundation
import LFKit
import SwiftUI

/// Builds a small throwaway git repository for SwiftUI previews, so every view shows real data:
/// history with a feature branch and a tag, a stash, a remote, local edits and a merge stopped on a conflict.
@MainActor
enum PreviewData {
    private static var cachedRoot: URL?

    /// A model on the sample repository, already refreshed.
    static func repository() async -> RepositoryModel? {
        guard let root = cachedRoot ?? build() else { return nil }
        cachedRoot = root
        guard let model = try? RepositoryModel.open(at: root) else { return nil }
        await model.refresh()
        await model.history.reload()
        return model
    }

    private static func build() -> URL? {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-preview-\(UUID().uuidString)")
        let work = base.appendingPathComponent("LF-Sample")
        let remote = base.appendingPathComponent("origin.git")
        let identity = [
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_AUTHOR_NAME": "Ada Lovelace", "GIT_AUTHOR_EMAIL": "ada@example.com",
            "GIT_COMMITTER_NAME": "Ada Lovelace", "GIT_COMMITTER_EMAIL": "ada@example.com",
        ]
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
            let origin = Git(directory: remote), git = Git(directory: work)
            func run(_ arguments: String..., allowFailure: Bool = false) throws {
                try git.run(arguments, environment: identity, allowedStatuses: allowFailure ? [0, 1, 128] : [0])
            }
            func write(_ path: String, _ text: String) throws {
                let url = work.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            func commit(_ message: String) throws {
                try run("add", "-A")
                try run("commit", "-q", "-m", message)
            }
            try origin.run(["init", "-q", "--bare", "-b", "main"], environment: identity)
            try run("init", "-q", "-b", "main")
            try write("README.md", "# LF-Sample\n\nA sample project for previews.\n")
            try write("Sources/App.swift", "import Foundation\n\nlet greeting = \"Hello\"\nlet version = 1\nprint(greeting)\n")
            try commit("Initial commit")
            try run("tag", "-a", "v1.0", "-m", "First release")
            try write("Sources/Util.swift", "func double(_ x: Int) -> Int { x * 2 }\n")
            try commit("Add utility helpers")
            try run("remote", "add", "origin", remote.path)
            try run("push", "-q", "-u", "origin", "main")

            try run("checkout", "-q", "-b", "feature/greeting")
            try write("Sources/App.swift", "import Foundation\n\nlet greeting = \"Hi there\"\nlet version = 1\nprint(greeting)\n")
            try commit("Friendlier greeting")
            try write("README.md", "# LF-Sample\n\nA sample project for previews.\n\n## Usage\nRun the app.\n")
            try commit("Document usage")
            try run("push", "-q", "-u", "origin", "feature/greeting")

            try run("checkout", "-q", "main")
            try write("Sources/App.swift", "import Foundation\n\nlet greeting = \"Welcome\"\nlet version = 2\nprint(greeting)\n")
            try commit("Bump version and reword greeting")
            try write("Sources/Util.swift", "func double(_ x: Int) -> Int { x * 2 }\nfunc triple(_ x: Int) -> Int { x * 3 }\n")
            try run("stash", "push", "-q", "-m", "WIP: triple helper")
            try run("merge", "--no-edit", "feature/greeting", allowFailure: true)

            // Local edits next to the conflict: a changed file and a new one.
            try write("README.md", "# LF-Sample\n\nA sample project for previews.\n\n## Usage\nRun the app from Xcode.\n")
            try write("Notes.txt", "remember to ship\n")
            return work
        } catch {
            return nil
        }
    }
}

/// Hosts a view that needs a loaded repository: shows a spinner while the sample repository is built.
struct PreviewRepository<Content: View>: View {
    @State private var repository: RepositoryModel?
    @State private var app = AppModel()
    private let size: CGSize?
    private let content: (RepositoryModel, AppModel) -> Content

    init(width: CGFloat? = nil, height: CGFloat? = nil,
         @ViewBuilder content: @escaping (RepositoryModel, AppModel) -> Content) {
        size = width.flatMap { w in height.map { CGSize(width: w, height: $0) } }
        self.content = content
    }

    var body: some View {
        Group {
            if let repository {
                content(repository, app)
            } else {
                ProgressView("Building sample repository…")
            }
        }
        .frame(width: size?.width, height: size?.height)
        .task { repository = await PreviewData.repository() }
    }
}
#endif
