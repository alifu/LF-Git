import ArgumentParser
import Foundation
import LFKit

public struct InstallCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Register lfgit as a git merge tool and merge driver.",
        discussion: """
        Writes `merge.tool`, `mergetool.lfgit.*` and `merge.lfgit.*` to the repository's git config \
        (or to your global config with --global). Use --attributes to also route files such as \
        *.pbxproj through the merge driver. Nothing is changed until you run this command; \
        --dry-run shows what would happen.
        """
    )

    private static let mergeToolKey = "merge.tool"
    private static let toolName = "lfgit"
    private static let missingKeyStatus: Int32 = 5

    @OptionGroup public var global: GlobalOptions

    @Flag(name: .customLong("global"), help: "Configure for all repositories instead of only this one.")
    var useGlobalConfig = false
    @Flag(help: "Remove what `install` added.")
    var uninstall = false
    @Flag(name: .customLong("dry-run"), help: "Print the changes without making them.")
    var dryRun = false
    @Option(help: "How git should invoke lfgit (default: lfgit, found through PATH).")
    var executable = "lfgit"
    @Option(name: .customLong("attributes"), help: ArgumentHelp("Add `<pattern> merge=lfgit` to .gitattributes (repeatable).", valueName: "pattern"))
    var attributes: [String] = []

    public init() {}

    public func run() throws {
        try finish(execute(console: StandardConsole()))
    }

    private var entries: [(key: String, value: String)] {
        let command = Self.shellQuoted(executable)
        return [
            (Self.mergeToolKey, Self.toolName),
            ("mergetool.lfgit.cmd", #"\#(command) mergetool "$BASE" "$LOCAL" "$REMOTE" "$MERGED""#),
            ("mergetool.lfgit.trustExitCode", "true"),
            ("merge.lfgit.name", "LF-Git merge driver"),
            ("merge.lfgit.driver", "\(command) driver %O %A %B %L %P"),
        ]
    }

    public func execute(console: Console) throws -> Int32 {
        let git = global.git
        // Local config and .gitattributes need a repository; plain --global does not.
        let root = (useGlobalConfig && attributes.isEmpty) ? nil : try git.repositoryRoot()
        let scope = useGlobalConfig ? "--global" : "--local"
        for entry in entries {
            try apply(entry, scope: scope, git: git, console: console)
        }
        if let root {
            try updateAttributes(root: root, console: console)
        }
        return 0
    }

    private func apply(_ entry: (key: String, value: String), scope: String, git: Git, console: Console) throws {
        if uninstall {
            try remove(entry, scope: scope, git: git, console: console)
        } else if let other = try existingMergeTool(for: entry, scope: scope, git: git) {
            console.line("kept merge.tool = \(other); run `git mergetool --tool=lfgit` to use lfgit")
        } else if dryRun {
            console.line("git config \(scope) \(entry.key) \(Self.shellQuoted(entry.value))")
        } else {
            try git.run(["config", scope, entry.key, entry.value])
            console.line("set \(entry.key) = \(entry.value)")
        }
    }

    /// The merge.tool someone else already configured, which `install` must not replace.
    private func existingMergeTool(for entry: (key: String, value: String), scope: String, git: Git) throws -> String? {
        guard entry.key == Self.mergeToolKey else { return nil }
        let current = try git.run(["config", scope, "--get", entry.key], allowedStatuses: [0, 1]).text
        return current.isEmpty || current == Self.toolName ? nil : current
    }

    private func remove(_ entry: (key: String, value: String), scope: String, git: Git, console: Console) throws {
        // Never remove a merge.tool that someone else chose.
        if entry.key == Self.mergeToolKey {
            let current = try git.run(["config", scope, "--get", entry.key], allowedStatuses: [0, 1]).text
            guard current == Self.toolName else { return }
        }
        if dryRun {
            console.line("git config \(scope) --unset \(entry.key)")
            return
        }
        let result = try git.run(["config", scope, "--unset", entry.key], allowedStatuses: [0, Self.missingKeyStatus])
        if result.status == 0 {
            console.line("removed \(entry.key)")
        }
    }

    private func updateAttributes(root: URL, console: Console) throws {
        let file = root.appendingPathComponent(".gitattributes")
        let existing = try readAttributes(file)
        var lines = existing.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let suffix = " merge=\(Self.toolName)"
        var updated = lines
        if uninstall {
            updated = lines.filter { !$0.hasSuffix(suffix) }
        } else {
            for pattern in attributes where !lines.contains(pattern + suffix) {
                updated.append(pattern + suffix)
            }
        }
        guard updated != lines else { return }
        if dryRun {
            console.line("update \(file.path): \(updated.count - lines.count) line(s) \(uninstall ? "removed" : "added")")
            return
        }
        let content = updated.isEmpty ? "" : updated.joined(separator: "\n") + "\n"
        try content.write(to: file, atomically: true, encoding: .utf8)
        console.line("updated .gitattributes")
    }

    /// The file's text, or "" if it does not exist. Anything unreadable is an error: never rewrite what we could not read.
    private func readAttributes(_ file: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: file.path) else { return "" }
        guard let data = FileManager.default.contents(atPath: file.path) else {
            throw CLIError("cannot read \(file.path); not touching it")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIError("\(file.path) is not valid UTF-8; add the lines by hand so nothing is lost")
        }
        return text
    }

    /// Quotes `text` for a POSIX shell only when it needs it.
    static func shellQuoted(_ text: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:@%+=,-")
        if !text.isEmpty, text.unicodeScalars.allSatisfy(safe.contains) {
            return text
        }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
