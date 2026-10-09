import Foundation
import LFKit

/// Keeps the user's own git configuration (merge.conflictStyle, hooks, signing...) out of the tests.
private let isolatedGitEnvironment: Void = {
    setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
    setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
    setenv("GIT_TERMINAL_PROMPT", "0", 1)
    // Submodules in the tests live in local directories, which git refuses to clone by default.
    setenv("GIT_CONFIG_COUNT", "1", 1)
    setenv("GIT_CONFIG_KEY_0", "protocol.file.allow", 1)
    setenv("GIT_CONFIG_VALUE_0", "always", 1)
}()

public struct ConflictSpec {
    public let path: String
    public let base: [UInt8]
    public let ours: [UInt8]
    public let theirs: [UInt8]
    /// Theirs deletes the file instead of changing it (a modify/delete conflict).
    public var theirsDeletes = false

    public init(path: String, base: String, ours: String, theirs: String) {
        self.init(path: path, base: Array(base.utf8), ours: Array(ours.utf8), theirs: Array(theirs.utf8))
    }

    public init(path: String, base: [UInt8], ours: [UInt8], theirs: [UInt8]) {
        self.path = path
        self.base = base
        self.ours = ours
        self.theirs = theirs
    }

    /// Three lines where line 2 is changed differently on each side.
    public static func text(_ path: String, line: String = "b") -> ConflictSpec {
        ConflictSpec(
            path: path,
            base: "a\n\(line)\nc\n",
            ours: "a\n\(line)-ours\nc\n",
            theirs: "a\n\(line)-theirs\nc\n"
        )
    }
}

/// A throwaway git repository, optionally left in the middle of a conflicted merge.
public final class GitFixture: @unchecked Sendable {
    public let sandbox = Sandbox()
    public let git: Git
    /// Bare repositories created by `addOrigin`, kept alive as long as the fixture.
    private var remotes: [Sandbox] = []

    public var directory: URL { sandbox.root }
    public var path: String { sandbox.root.path }

    public init() throws {
        _ = isolatedGitEnvironment
        git = Git(directory: sandbox.root)
        try git.run(["init", "-q", "-b", "main"])
        try git.run(["config", "user.name", "Test"])
        try git.run(["config", "user.email", "test@example.com"])
        try git.run(["config", "commit.gpgsign", "false"])
    }

    /// A working copy cloned from `remote`, which must contain a `main` branch.
    public init(cloning remote: URL) throws {
        _ = isolatedGitEnvironment
        git = Git(directory: sandbox.root)
        try git.run(["clone", "-q", remote.path, sandbox.root.path])
        try git.run(["config", "user.name", "Test"])
        try git.run(["config", "user.email", "test@example.com"])
        try git.run(["config", "commit.gpgsign", "false"])
    }

    /// Writes a file and commits everything; returns the new commit's full hash.
    @discardableResult
    public func commit(_ path: String, _ text: String, message: String? = nil) throws -> String {
        sandbox.write(path, text)
        try commitAll(message ?? "update \(path)")
        return try git.run(["rev-parse", "HEAD"]).text
    }

    /// A bare repository registered as `origin`; `main` is pushed to it and tracks it.
    @discardableResult
    public func addOrigin() throws -> URL {
        let bare = Sandbox()
        try Git(directory: bare.root).run(["init", "-q", "--bare", "-b", "main"])
        remotes.append(bare)
        try git.run(["remote", "add", "origin", bare.root.path])
        try git.run(["push", "-q", "-u", "origin", "main"])
        return bare.root
    }

    public func commitAll(_ message: String) throws {
        try git.run(["add", "-A"])
        try git.run(["commit", "-q", "-m", message])
    }

    /// Commits `specs` on main and a feature branch, then merges so every file conflicts.
    public func makeConflicts(_ specs: [ConflictSpec], diff3: Bool = false) throws {
        if diff3 { try git.run(["config", "merge.conflictStyle", "diff3"]) }
        for spec in specs { sandbox.write(spec.path, bytes: spec.base) }
        try commitAll("base")
        try git.run(["checkout", "-q", "-b", "feature"])
        for spec in specs {
            if spec.theirsDeletes {
                try FileManager.default.removeItem(atPath: sandbox.path(spec.path))
            } else {
                sandbox.write(spec.path, bytes: spec.theirs)
            }
        }
        try commitAll("theirs")
        try git.run(["checkout", "-q", "main"])
        for spec in specs { sandbox.write(spec.path, bytes: spec.ours) }
        try commitAll("ours")
        try git.run(["merge", "feature"], allowedStatuses: [0, 1])
    }

    public func conflictedPaths() throws -> [String] {
        try git.conflictedPaths()
    }

    public func read(_ relativePath: String) -> String {
        sandbox.readText(sandbox.path(relativePath))
    }
}
