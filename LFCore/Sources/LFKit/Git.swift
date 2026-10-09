import Foundation

public enum GitError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case launchFailed(String)
    case failed(arguments: [String], status: Int32, stderr: String)
    case notARepository(String)
    /// git succeeded but printed something this app does not understand.
    case unexpectedOutput(String)
    /// The caller stopped the command.
    case cancelled
    /// The command ran longer than its time limit and was stopped.
    case timedOut(seconds: TimeInterval)

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
        case .cancelled:
            "cancelled"
        case .timedOut(let seconds):
            "timed out after \(Int(seconds)) s"
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
    /// Every command run through this value is recorded here.
    public let log: GitCommandLog?

    private static let defaultMarkerSize = Int(LFDefaults.markerSize)
    /// How long a stopped command gets to clean up before it is killed.
    private static let gracePeriod: TimeInterval = 2

    public init(directory: URL, log: GitCommandLog? = nil) {
        self.directory = directory
        self.log = log
    }

    /// Runs `git` and waits for it.
    /// - Parameters:
    ///   - stdin: bytes fed to git's standard input (through a temporary file, so large input cannot deadlock).
    ///   - environment: extra variables for this call (the app's own settings below always apply).
    ///   - outputFile: when set, standard output goes to this file instead of `GitResult.stdout`, so huge
    ///     output (a diff of a million lines) never has to fit in memory.
    ///   - timeout: stop the command (`GitError.timedOut`) if it runs longer than this many seconds.
    ///   - cancellation: lets another thread stop the command (`GitError.cancelled`).
    @discardableResult
    public func run(_ arguments: [String], stdin: Data? = nil, outputFile: URL? = nil, environment: [String: String] = [:],
                    allowedStatuses: Set<Int32> = [0], timeout: TimeInterval? = nil,
                    cancellation: GitCancellation? = nil) throws(GitError) -> GitResult {
        let started = Date()
        var status: Int32 = -1
        defer { log?.record(arguments: arguments, status: status, duration: Date().timeIntervalSince(started)) }
        if cancellation?.isCancelled == true { throw .cancelled }
        let result = try execute(arguments, stdin: stdin, outputFile: outputFile, environment: environment,
                                 timeout: timeout, cancellation: cancellation)
        status = result.status
        guard allowedStatuses.contains(result.status) else {
            throw .failed(arguments: arguments, status: result.status, stderr: result.stderr)
        }
        return result
    }

    private func execute(_ arguments: [String], stdin: Data?, outputFile: URL?, environment: [String: String],
                         timeout: TimeInterval?, cancellation: GitCancellation?) throws(GitError) -> GitResult {
        let scratch = FileManager.default.temporaryDirectory
        let errorFile = scratch.appendingPathComponent("lfgit-git-\(UUID().uuidString).err")
        // Output goes to a file, never a pipe: a pipe stays open as long as any child of git (ssh, a hook)
        // lives, which would keep a cancelled command waiting.
        let outputURL = outputFile ?? scratch.appendingPathComponent("lfgit-git-\(UUID().uuidString).out")
        var inputFile: URL?
        var handles: [FileHandle] = []
        defer {
            handles.forEach { try? $0.close() }
            try? FileManager.default.removeItem(at: errorFile)
            if outputFile == nil { try? FileManager.default.removeItem(at: outputURL) }
            if let inputFile { try? FileManager.default.removeItem(at: inputFile) }
        }
        func open(_ url: URL, forWriting: Bool, what: String) throws(GitError) -> FileHandle {
            if forWriting { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? (forWriting ? FileHandle(forWritingTo: url) : FileHandle(forReadingFrom: url)) else {
                throw .launchFailed("cannot create a temporary file for git's \(what)")
            }
            handles.append(handle)
            return handle
        }

        let errorHandle = try open(errorFile, forWriting: true, what: "error output")
        let outputHandle = try open(outputURL, forWriting: true, what: "output")
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
        if let stdin {
            let url = scratch.appendingPathComponent("lfgit-git-\(UUID().uuidString).in")
            inputFile = url
            guard (try? stdin.write(to: url)) != nil else {
                throw .launchFailed("cannot create a temporary file for git's input")
            }
            process.standardInput = try open(url, forWriting: false, what: "input")
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        let stopper = ProcessStopper(process: process, gracePeriod: Self.gracePeriod)
        do {
            try process.run()
        } catch {
            throw .launchFailed(error.localizedDescription)
        }
        let cancelKey = cancellation?.onCancel { stopper.stop(.cancelled) }
        let timer = timeout.map { seconds -> DispatchSourceTimer in
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + seconds)
            timer.setEventHandler { stopper.stop(.timedOut(seconds: seconds)) }
            timer.resume()
            return timer
        }
        process.waitUntilExit()
        timer?.cancel()
        if let cancelKey { cancellation?.remove(cancelKey) }

        if let reason = stopper.reason { throw reason }
        if process.terminationReason == .uncaughtSignal {
            throw .failed(arguments: arguments, status: process.terminationStatus, stderr: "terminated by signal \(process.terminationStatus)")
        }
        let errorText = (try? Data(contentsOf: errorFile)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let output = outputFile == nil ? ((try? Data(contentsOf: outputURL)) ?? Data()) : Data()
        return GitResult(status: process.terminationStatus, stdout: output,
                         stderr: errorText.trimmingCharacters(in: .whitespacesAndNewlines))
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

/// Stops a running process politely (SIGTERM, so git can clean up its lock files), then by force.
private final class ProcessStopper: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let gracePeriod: TimeInterval
    private var firstReason: GitError?

    init(process: Process, gracePeriod: TimeInterval) {
        self.process = process
        self.gracePeriod = gracePeriod
    }

    /// Why the process was stopped, if it was.
    var reason: GitError? {
        lock.withLock { firstReason }
    }

    func stop(_ reason: GitError) {
        let isFirst: Bool = lock.withLock {
            guard firstReason == nil else { return false }
            firstReason = reason
            return true
        }
        guard isFirst, process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + gracePeriod) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}
