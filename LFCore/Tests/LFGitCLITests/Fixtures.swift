import Foundation
@testable import LFGitCLI
import LFKit

/// Keeps the user's own git configuration (merge.conflictStyle, hooks, signing...) out of the tests.
private let isolatedGitEnvironment: Void = {
    setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
    setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
    setenv("GIT_TERMINAL_PROMPT", "0", 1)
}()

/// A console that records output and replays scripted input.
final class BufferConsole: Console {
    var palette: TerminalPalette?
    private(set) var output = ""
    private(set) var errors = ""
    private(set) var prompts: [String] = []
    private var inputs: [String]

    init(inputs: [String] = [], palette: TerminalPalette? = nil) {
        self.inputs = inputs
        self.palette = palette
    }

    func write(_ text: String) { output += text }
    func writeError(_ text: String) { errors += text }

    func readLine(prompt: String) -> String? {
        prompts.append(prompt)
        return inputs.isEmpty ? nil : inputs.removeFirst()
    }
}

struct ConflictSpec {
    let path: String
    let base: [UInt8]
    let ours: [UInt8]
    let theirs: [UInt8]

    init(path: String, base: String, ours: String, theirs: String) {
        self.init(path: path, base: Array(base.utf8), ours: Array(ours.utf8), theirs: Array(theirs.utf8))
    }

    init(path: String, base: [UInt8], ours: [UInt8], theirs: [UInt8]) {
        self.path = path
        self.base = base
        self.ours = ours
        self.theirs = theirs
    }

    /// Three lines where line 2 is changed differently on each side.
    static func text(_ path: String, line: String = "b") -> ConflictSpec {
        ConflictSpec(
            path: path,
            base: "a\n\(line)\nc\n",
            ours: "a\n\(line)-ours\nc\n",
            theirs: "a\n\(line)-theirs\nc\n"
        )
    }
}

/// A throwaway git repository, optionally left in the middle of a conflicted merge.
final class GitFixture {
    let sandbox = Sandbox()
    let git: Git

    var directory: URL { sandbox.root }
    var path: String { sandbox.root.path }

    init() throws {
        _ = isolatedGitEnvironment
        git = Git(directory: sandbox.root)
        try git.run(["init", "-q", "-b", "main"])
        try git.run(["config", "user.name", "Test"])
        try git.run(["config", "user.email", "test@example.com"])
        try git.run(["config", "commit.gpgsign", "false"])
    }

    func commitAll(_ message: String) throws {
        try git.run(["add", "-A"])
        try git.run(["commit", "-q", "-m", message])
    }

    /// Commits `specs` on main and a feature branch, then merges so every file conflicts.
    func makeConflicts(_ specs: [ConflictSpec], diff3: Bool = false) throws {
        if diff3 { try git.run(["config", "merge.conflictStyle", "diff3"]) }
        for spec in specs { sandbox.write(spec.path, bytes: spec.base) }
        try commitAll("base")
        try git.run(["checkout", "-q", "-b", "feature"])
        for spec in specs { sandbox.write(spec.path, bytes: spec.theirs) }
        try commitAll("theirs")
        try git.run(["checkout", "-q", "main"])
        for spec in specs { sandbox.write(spec.path, bytes: spec.ours) }
        try commitAll("ours")
        try git.run(["merge", "feature"], allowedStatuses: [0, 1])
    }

    func conflictedPaths() throws -> [String] {
        try git.conflictedPaths()
    }

    func read(_ relativePath: String) -> String {
        sandbox.readText(sandbox.path(relativePath))
    }
}
