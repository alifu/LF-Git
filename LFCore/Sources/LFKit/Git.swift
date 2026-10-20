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
                + (Self.isLoginProblem(stderr) ? "\n\(Self.loginHint)" : "")
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

    private static let loginHint = "Sign in first: add an access token or password under Settings › Git server accounts, "
        + "or use an SSH key that is loaded in your agent."

    private static func isLoginProblem(_ stderr: String) -> Bool {
        let signs = ["could not read Username", "could not read Password", "Authentication failed", "terminal prompts disabled",
                     "Permission denied (publickey", "HTTP Basic: Access denied", "Invalid username or password"]
        return signs.contains { stderr.localizedCaseInsensitiveContains($0) }
    }
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
    ///   - onStandardError: receives git's error output while the command runs (progress of a clone, for instance).
    ///   - literalPathspecs: treat paths as plain names. A few commands (`git stash`) use magic pathspecs
    ///     such as `:/` themselves and need this off; their callers then write `:(literal)name` explicitly.
    @discardableResult
    public func run(_ arguments: [String], stdin: Data? = nil, outputFile: URL? = nil, environment: [String: String] = [:],
                    allowedStatuses: Set<Int32> = [0], timeout: TimeInterval? = nil,
                    cancellation: GitCancellation? = nil, onStandardError: (@Sendable (String) -> Void)? = nil,
                    literalPathspecs: Bool = true) throws(GitError) -> GitResult {
        let started = Date()
        var status: Int32 = -1
        defer { log?.record(arguments: arguments, status: status, duration: Date().timeIntervalSince(started)) }
        if cancellation?.isCancelled == true { throw .cancelled }
        let result = try execute(arguments, stdin: stdin, outputFile: outputFile, environment: environment,
                                 timeout: timeout, cancellation: cancellation, onStandardError: onStandardError,
                                 literalPathspecs: literalPathspecs)
        status = result.status
        guard allowedStatuses.contains(result.status) else {
            throw .failed(arguments: arguments, status: result.status, stderr: result.stderr)
        }
        return result
    }

    /// Bytes of path arguments per git process. The OS refuses a command line over `ARG_MAX` (1 MB on macOS, shared
    /// with the environment), and launching then fails outright, so a folder with tens of thousands of changed
    /// files must reach git in several runs.
    public static let pathBatchBytes = 128 * 1024

    /// Splits `paths` into runs that each fit a command line.
    public static func batches(of paths: [String], maxBytes: Int = pathBatchBytes) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var currentBytes = 0
        for path in paths {
            let size = path.utf8.count + 1
            if !current.isEmpty, currentBytes + size > maxBytes {
                result.append(current)
                current = []
                currentBytes = 0
            }
            current.append(path)
            currentBytes += size
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Runs `prefix` followed by `paths`, in as many git processes as the command-line limit requires.
    public func runBatched(_ prefix: [String], paths: [String]) throws(GitError) {
        for batch in Self.batches(of: paths) {
            try run(prefix + batch)
        }
    }

    private func execute(_ arguments: [String], stdin: Data?, outputFile: URL?, environment: [String: String],
                         timeout: TimeInterval?, cancellation: GitCancellation?,
                         onStandardError: (@Sendable (String) -> Void)?, literalPathspecs: Bool) throws(GitError) -> GitResult {
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
            .merging(GitEnvironment.shared.current) { _, new in new }
            .merging(environment) { _, new in new }
            .merging([
                "GIT_TERMINAL_PROMPT": "0",
                // `git status` would otherwise refresh the index under a lock, and a stage that runs at the
                // same time fails with "index.lock exists". The app only ever needs read-only status.
                "GIT_OPTIONAL_LOCKS": "0",
                // Paths are file names, never patterns: a file called `*.log` must not match every log file.
                "GIT_LITERAL_PATHSPECS": literalPathspecs ? "1" : "0",
            ]) { _, new in new }
        if let stdin {
            let url = scratch.appendingPathComponent("lfgit-git-\(UUID().uuidString).in")
            inputFile = url
            // Input may hold a password: only this user may read it, even for the moment it exists.
            guard Self.writePrivately(stdin, to: url) else {
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
        let timer = timeout.map { seconds in Watchdog(after: seconds) { stopper.stop(.timedOut(seconds: seconds)) } }
        let tailer = onStandardError.map { StandardErrorTailer(file: errorFile, deliver: $0) }
        process.waitUntilExit()
        tailer?.finish()
        timer?.cancel()
        if let cancelKey { cancellation?.remove(cancelKey) }

        if let reason = stopper.reason, process.terminationReason == .uncaughtSignal || process.terminationStatus != 0 { throw reason }
        if process.terminationReason == .uncaughtSignal {
            throw .failed(arguments: arguments, status: process.terminationStatus, stderr: "terminated by signal \(process.terminationStatus)")
        }
        let errorText = (try? Data(contentsOf: errorFile)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let output = outputFile == nil ? ((try? Data(contentsOf: outputURL)) ?? Data()) : Data()
        return GitResult(status: process.terminationStatus, stdout: output,
                         stderr: errorText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Creates the file with mode 0600 from the start (O_EXCL, so nothing pre-planted is followed).
    private static func writePrivately(_ data: Data, to url: URL) -> Bool {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        return (try? handle.write(contentsOf: data)) != nil
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
        try runBatched(["add", "--"], paths: paths)
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
final class ProcessStopper: @unchecked Sendable {
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
        // A command that already finished on its own is not "cancelled", whatever the timer says.
        let isFirst: Bool = lock.withLock {
            guard firstReason == nil, process.isRunning else { return false }
            firstReason = reason
            return true
        }
        guard isFirst else { return }
        let pid = process.processIdentifier
        let children = Self.descendants(of: pid)
        process.terminate()
        // ssh, hooks and shell pipelines are children of git: stop them too, or the work goes on unseen.
        children.forEach { kill($0, SIGTERM) }
        _ = Watchdog(after: gracePeriod) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
            children.forEach { kill($0, SIGKILL) }
        }
    }

    /// Every process below `root`, found through `ps`.
    private static func descendants(of root: pid_t) -> [pid_t] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-A", "-o", "pid=,ppid="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        var children: [pid_t: [pid_t]] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let numbers = line.split(separator: " ").compactMap { pid_t($0) }
            if numbers.count == 2 { children[numbers[1], default: []].append(numbers[0]) }
        }
        var found: [pid_t] = [], queue = children[root] ?? []
        while let next = queue.popLast() {
            found.append(next)
            queue += children[next] ?? []
        }
        return found
    }
}
