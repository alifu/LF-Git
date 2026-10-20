import Foundation

/// What `git ls-remote` found on a server.
public struct RemoteProbe: Equatable, Sendable {
    /// Every branch name, the default one first.
    public let branches: [String]
    /// The branch `HEAD` points to; nil on an empty repository.
    public let defaultBranch: String?

    public init(branches: [String], defaultBranch: String?) {
        self.branches = branches
        self.defaultBranch = defaultBranch
    }
}

/// Looks at and clones repositories that are not on this machine yet, so there is no `GitClient` to ask.
public enum GitClone {
    /// A reachability check should answer in seconds; the 5 minutes of a fetch would leave a person staring at a spinner.
    public static let probeTimeout: TimeInterval = 8

    /// Safe defaults for every contact with a server: no `ext::` helpers, which run arbitrary commands.
    private static let safety = ["-c", "protocol.ext.allow=never"]

    /// Asks the server for its branches. This is the cheapest proof that the address is right and the login works.
    public static func probe(_ url: RemoteURL, credentials: CloneCredentials? = nil, timeout: TimeInterval = probeTimeout,
                             cancellation: GitCancellation? = nil, log: GitCommandLog? = nil) throws(GitError) -> RemoteProbe {
        let askpass = try AskpassScript(credentials: credentials ?? url.embeddedLogin)
        defer { askpass?.remove() }
        let result = try Git(directory: FileManager.default.temporaryDirectory, log: log)
            .run(safety + ["ls-remote", "--symref", "--", url.text, "HEAD", "refs/heads/*"],
                 environment: askpass?.environment ?? [:], timeout: timeout, cancellation: cancellation)
        return parseProbe(result.text)
    }

    static func parseProbe(_ output: String) -> RemoteProbe {
        var defaultBranch: String?
        var branches: [String] = []
        let prefix = "refs/heads/"
        for line in output.split(separator: "\n") {
            if line.hasPrefix("ref: \(prefix)"), line.hasSuffix("\tHEAD"),
               let name = line.dropFirst("ref: \(prefix)".count).split(separator: "\t").first {
                defaultBranch = String(name)
            } else if let ref = line.split(separator: "\t").last, ref.hasPrefix(prefix) {
                branches.append(String(ref.dropFirst(prefix.count)))
            }
        }
        branches.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        if let defaultBranch, let index = branches.firstIndex(of: defaultBranch) {
            branches.remove(at: index)
            branches.insert(defaultBranch, at: 0)
        }
        return RemoteProbe(branches: branches, defaultBranch: defaultBranch)
    }

    /// Clones into `request.destination` and returns it. A folder this call created is removed again if the clone
    /// fails or is cancelled; a folder that was already there is left as it was found.
    @discardableResult
    public static func clone(_ request: CloneRequest, cancellation: GitCancellation? = nil, log: GitCommandLog? = nil,
                             progress: (@Sendable (CloneProgress) -> Void)? = nil) throws -> URL {
        let name = request.folderName
        guard !name.isEmpty, !name.contains("/"), name != ".", name != "..", !name.hasPrefix("-") else { throw CloneProblem.invalidFolderName }
        let destination = request.destination
        let existed = try prepare(destination)
        let askpass = try AskpassScript(credentials: request.credentials ?? request.url.embeddedLogin)
        defer { askpass?.remove() }
        var onStandardError: (@Sendable (String) -> Void)?
        if let progress {
            onStandardError = { chunk in
                if let latest = CloneProgress.latest(in: chunk) { progress(latest) }
            }
        }
        do {
            try Git(directory: FileManager.default.temporaryDirectory, log: log)
                .run(safety + arguments(for: request), environment: askpass?.environment ?? [:], cancellation: cancellation,
                     onStandardError: onStandardError)
        } catch {
            if !existed { try? FileManager.default.removeItem(at: destination) }
            throw error
        }
        return destination
    }

    static func arguments(for request: CloneRequest) -> [String] {
        var arguments = ["clone", "--progress"]
        if let branch = request.branch {
            arguments += ["--branch", branch]
        }
        if request.singleBranch { arguments.append("--single-branch") }
        if request.recurseSubmodules { arguments.append("--recurse-submodules") }
        if request.shallow { arguments += ["--depth", "1"] }
        return arguments + ["--", request.url.text, request.destination.path]
    }

    /// True when the folder was already there (and empty); throws when it holds anything.
    private static func prepare(_ destination: URL) throws -> Bool {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: destination.path, isDirectory: &isDirectory) else { return false }
        guard isDirectory.boolValue, (try? manager.contentsOfDirectory(atPath: destination.path))?.isEmpty == true else {
            throw CloneProblem.destinationNotEmpty(destination.path)
        }
        return true
    }
}

extension RemoteURL {
    /// A login typed into an https address, when there is one.
    fileprivate var embeddedLogin: CloneCredentials? {
        guard let embeddedPassword else { return nil }
        return CloneCredentials(username: embeddedUsername ?? "", password: embeddedPassword)
    }
}

/// A throw-away program for git's `GIT_ASKPASS` that answers with a login given in the environment, so the password
/// never appears in a command line, a log or a file.
private struct AskpassScript {
    private let directory: URL
    let environment: [String: String]

    private static let source = """
    #!/bin/sh
    case "$1" in
      Username*) printf '%s\\n' "$LFGIT_ASKPASS_USER" ;;
      *) printf '%s\\n' "$LFGIT_ASKPASS_PASSWORD" ;;
    esac
    """

    /// nil when there is no login to offer.
    init?(credentials: CloneCredentials?) throws(GitError) {
        guard let credentials else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-askpass-\(UUID().uuidString)", isDirectory: true)
        let script = directory.appendingPathComponent("askpass.sh")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try Data(Self.source.utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw .launchFailed("cannot prepare the sign-in helper: \(error.localizedDescription)")
        }
        self.directory = directory
        environment = ["GIT_ASKPASS": script.path, "LFGIT_ASKPASS_USER": credentials.username,
                       "LFGIT_ASKPASS_PASSWORD": credentials.password]
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
