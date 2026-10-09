import Foundation

public enum GitError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case launchFailed(String)
    case failed(arguments: [String], status: Int32, stderr: String)
    case notARepository(String)
    /// git succeeded but printed something this app does not understand.
    case unexpectedOutput(String)

    public var description: String {
        switch self {
        case .launchFailed(let reason):
            "cannot run git: \(reason)"
        case .failed(let arguments, let status, let stderr):
            "git \(arguments.joined(separator: " ")) failed (exit \(status))" + (stderr.isEmpty ? "" : ": \(stderr)")
        case .notARepository(let path):
            "'\(path)' is not inside a git repository"
        case .unexpectedOutput(let what):
            "unexpected output from git (\(what))"
        }
    }

    public var errorDescription: String? { description }
}

public struct GitResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: String

    public var text: String {
        String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Runs the user's own `git`, so credentials, hooks and configuration behave exactly as in a terminal.
public struct Git: Sendable {
    public let directory: URL

    private static let defaultMarkerSize = Int(LFDefaults.markerSize)

    public init(directory: URL) {
        self.directory = directory
    }

    /// Runs `git` and waits for it.
    /// - Parameters:
    ///   - stdin: bytes fed to git's standard input (through a temporary file, so large input cannot deadlock).
    ///   - environment: extra variables for this call (the app's own settings below always apply).
    ///   - outputFile: when set, standard output goes to this file instead of `GitResult.stdout`, so huge
    ///     output (a diff of a million lines) never has to fit in memory.
    @discardableResult
    public func run(_ arguments: [String], stdin: Data? = nil, outputFile: URL? = nil, environment: [String: String] = [:],
                    allowedStatuses: Set<Int32> = [0]) throws(GitError) -> GitResult {
        let scratch = FileManager.default.temporaryDirectory
        let errorFile = scratch.appendingPathComponent("lfgit-git-\(UUID().uuidString).err")
        guard FileManager.default.createFile(atPath: errorFile.path, contents: nil),
              let errorHandle = try? FileHandle(forWritingTo: errorFile) else {
            throw .launchFailed("cannot create a temporary file for git's error output")
        }
        var inputFile: URL?
        defer {
            try? FileManager.default.removeItem(at: errorFile)
            if let inputFile { try? FileManager.default.removeItem(at: inputFile) }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment
            .merging(environment) { _, new in new }
            .merging([
                "GIT_TERMINAL_PROMPT": "0",
                // `git status` would otherwise refresh the index under a lock, and a stage that runs at the
                // same time fails with "index.lock exists". The app only ever needs read-only status.
                "GIT_OPTIONAL_LOCKS": "0",
                // Paths are file names, never patterns: a file called `*.log` must not match every log file.
                "GIT_LITERAL_PATHSPECS": "1",
            ]) { _, new in new }
        var inputHandle: FileHandle?
        if let stdin {
            let url = scratch.appendingPathComponent("lfgit-git-\(UUID().uuidString).in")
            inputFile = url
            guard (try? stdin.write(to: url)) != nil, let handle = try? FileHandle(forReadingFrom: url) else {
                try? errorHandle.close()
                throw .launchFailed("cannot create a temporary file for git's input")
            }
            inputHandle = handle
        }
        process.standardInput = inputHandle ?? FileHandle.nullDevice
        let outputPipe = Pipe()
        var outputHandle: FileHandle?
        if let outputFile {
            guard FileManager.default.createFile(atPath: outputFile.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: outputFile) else {
                try? errorHandle.close()
                try? inputHandle?.close()
                throw .launchFailed("cannot write \(outputFile.path)")
            }
            outputHandle = handle
            process.standardOutput = handle
        } else {
            process.standardOutput = outputPipe
        }
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            try? errorHandle.close()
            try? inputHandle?.close()
            try? outputHandle?.close()
            throw .launchFailed(error.localizedDescription)
        }
        let output = outputHandle == nil ? outputPipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        try? errorHandle.close()
        try? inputHandle?.close()
        try? outputHandle?.close()

        if process.terminationReason == .uncaughtSignal {
            throw .failed(arguments: arguments, status: process.terminationStatus, stderr: "terminated by signal \(process.terminationStatus)")
        }
        let errorText = (try? Data(contentsOf: errorFile)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let result = GitResult(
            status: process.terminationStatus,
            stdout: output,
            stderr: errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard allowedStatuses.contains(result.status) else {
            throw .failed(arguments: arguments, status: result.status, stderr: result.stderr)
        }
        return result
    }

    public func repositoryRoot() throws(GitError) -> URL {
        let result = try run(["rev-parse", "--show-toplevel"], allowedStatuses: [0, 128])
        guard result.status == 0, !result.text.isEmpty else {
            throw .notARepository(directory.path)
        }
        return URL(fileURLWithPath: result.text, isDirectory: true)
    }

    /// Paths with unmerged entries, relative to the repository root.
    public func conflictedPaths() throws(GitError) -> [String] {
        let result = try run(["diff", "--name-only", "--diff-filter=U", "-z"])
        return result.stdout.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Unmerged paths that one side deleted and the other changed (a modify/delete conflict).
    public func modifyDeletePaths() throws(GitError) -> [String] {
        // Each line: "<mode> <object> <stage>\t<path>"; stage 1 = base, 2 = ours, 3 = theirs.
        var stages: [String: Set<Character>] = [:]
        for record in try run(["ls-files", "-u", "-z"]).stdout.split(separator: 0) {
            let line = String(decoding: record, as: UTF8.self)
            guard let tab = line.firstIndex(of: "\t"), let stage = line[..<tab].last else { continue }
            stages[String(line[line.index(after: tab)...]), default: []].insert(stage)
        }
        return stages.filter { $0.value.contains("1") && $0.value.count == 2 }.map(\.key).sorted()
    }

    /// Length of conflict marker runs for a file: the `conflict-marker-size` attribute, or 7.
    public func markerSize(forPath path: String) -> Int {
        guard let result = try? run(["check-attr", "conflict-marker-size", "--", path]),
              let value = result.text.components(separatedBy: ": ").last,
              let size = Int(value), size > 0 else {
            return Self.defaultMarkerSize
        }
        return size
    }

    public func stage(_ paths: [String]) throws(GitError) {
        guard !paths.isEmpty else { return }
        try run(["add", "--"] + paths)
    }

    public enum Side: String, Sendable {
        case ours
        case theirs
    }

    /// Replaces a conflicted file with one whole side (used for binary files).
    public func checkout(_ side: Side, path: String) throws(GitError) {
        try run(["checkout", "--\(side.rawValue)", "--", path])
    }
}
