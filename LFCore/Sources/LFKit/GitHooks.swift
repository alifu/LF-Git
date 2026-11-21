import Foundation

/// One hook script of a repository, as git would find it.
public struct GitHook: Equatable, Sendable, Identifiable {
    public let name: String
    public let path: String
    /// Git skips a hook that is not executable, so the UI can say why nothing ran.
    public let isExecutable: Bool

    public var id: String { name }

    public init(name: String, path: String, isExecutable: Bool) {
        self.name = name
        self.path = path
        self.isExecutable = isExecutable
    }
}

extension GitClient {
    /// The hooks in the repository's hooks directory (`core.hooksPath` is honoured, so husky and lefthook show up).
    /// `*.sample` files are ignored. Sorted by name.
    public func hooks() throws -> [GitHook] {
        let located = try git.run(["rev-parse", "--git-path", "hooks"]).text
        guard !located.isEmpty else { return [] }
        let directory = URL(fileURLWithPath: located, relativeTo: git.directory).standardizedFileURL
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { !$0.hasSuffix(".sample") && !$0.hasPrefix(".") }
            .compactMap { name -> GitHook? in
                let path = directory.appendingPathComponent(name).path
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
                return GitHook(name: name, path: path, isExecutable: FileManager.default.isExecutableFile(atPath: path))
            }
            .sorted { $0.name < $1.name }
    }

    /// Whether git would run a hook of this name. Runs git once: call it off the main thread.
    public func hasHook(named name: String) -> Bool {
        hasHook(namedAnyOf: [name])
    }

    /// Whether git would run any of these hooks, from one listing of the hooks directory.
    public func hasHook(namedAnyOf names: [String]) -> Bool {
        ((try? hooks()) ?? []).contains { $0.isExecutable && names.contains($0.name) }
    }
}
