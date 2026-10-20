import Foundation

/// Why a URL or a destination cannot be used, before git is even asked.
public enum CloneProblem: Error, Equatable, LocalizedError, Sendable {
    case emptyURL
    case unsupportedURL
    case invalidFolderName
    case destinationNotEmpty(String)

    public var errorDescription: String? {
        switch self {
        case .emptyURL: "Enter the address of the repository."
        case .unsupportedURL: "Use an https://, ssh:// or git@host:path address."
        case .invalidFolderName: "Enter a folder name without slashes."
        case .destinationNotEmpty(let path): "\(path) already exists and is not empty."
        }
    }
}

/// A repository address that is safe to hand to git. Any login typed into the address is taken out of it: it would
/// otherwise end up in `.git/config` and in the command log.
public struct RemoteURL: Equatable, Sendable {
    public enum Transport: Equatable, Sendable {
        case http
        case ssh
        case file
    }

    /// The address to give git, without a password.
    public let text: String
    public let transport: Transport
    /// Server name (with `:port` when it is not the default); nil for a local path.
    public let host: String?
    /// Login found in an `https://user:password@host/…` address.
    public let embeddedUsername: String?
    public let embeddedPassword: String?

    /// The folder a clone would get by default: the last path component without `.git`.
    public var repositoryName: String {
        let path = text.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        return path.hasSuffix(".git") ? String(path.dropLast(4)) : path
    }

    private static let schemes: [String: Transport] = ["https": .http, "http": .http, "ssh": .ssh, "file": .file]
    /// `git@host:group/name.git`
    private static var scpLike: Regex<Substring> { /^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^\s:][^\s]*$/ }

    public static func parse(_ raw: String) throws(CloneProblem) -> RemoteURL {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { throw .emptyURL }
        // A leading dash would be read by git as an option; whitespace and control characters never belong in an address.
        guard !text.hasPrefix("-"), !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || $0.value < 0x20 })
        else { throw .unsupportedURL }

        if text.contains("://") {
            guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
                  let transport = schemes[scheme] else { throw .unsupportedURL }
            return try parse(components, transport: transport, original: text)
        }
        if text.wholeMatch(of: scpLike) != nil {
            let host = text.split(separator: "@", maxSplits: 1)[1].split(separator: ":", maxSplits: 1)[0]
            return RemoteURL(text: text, transport: .ssh, host: String(host), embeddedUsername: nil, embeddedPassword: nil)
        }
        throw .unsupportedURL
    }

    private static func parse(_ components: URLComponents, transport: Transport, original: String) throws(CloneProblem) -> RemoteURL {
        if transport == .file {
            guard !components.path.isEmpty else { throw .unsupportedURL }
            return RemoteURL(text: original, transport: .file, host: nil, embeddedUsername: nil, embeddedPassword: nil)
        }
        guard let hostName = components.host, !hostName.isEmpty else { throw .unsupportedURL }
        let host = components.port.map { "\(hostName):\($0)" } ?? hostName
        guard transport == .http else {
            // ssh keeps its user name (`ssh://git@host/…`); there is no password to take out.
            return RemoteURL(text: original, transport: .ssh, host: host, embeddedUsername: nil, embeddedPassword: nil)
        }
        var cleaned = components
        cleaned.user = nil
        cleaned.password = nil
        guard let text = cleaned.string else { throw .unsupportedURL }
        return RemoteURL(text: text, transport: .http, host: host,
                         embeddedUsername: components.percentEncodedUser?.removingPercentEncoding,
                         embeddedPassword: components.percentEncodedPassword?.removingPercentEncoding)
    }
}

public struct CloneCredentials: Equatable, Sendable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct CloneRequest: Sendable {
    public var url: RemoteURL
    /// The folder that will contain the clone.
    public var parent: URL
    public var folderName: String
    /// nil clones the server's default branch.
    public var branch: String?
    public var singleBranch: Bool
    public var recurseSubmodules: Bool
    public var shallow: Bool
    public var credentials: CloneCredentials?

    public init(url: RemoteURL, parent: URL, folderName: String, branch: String? = nil, singleBranch: Bool = true,
                recurseSubmodules: Bool = false, shallow: Bool = false, credentials: CloneCredentials? = nil) {
        self.url = url
        self.parent = parent
        self.folderName = folderName
        self.branch = branch
        self.singleBranch = singleBranch
        self.recurseSubmodules = recurseSubmodules
        self.shallow = shallow
        self.credentials = credentials
    }

    public var destination: URL { parent.appendingPathComponent(folderName, isDirectory: true) }
}

/// One line of `git clone --progress`: "Receiving objects:  42% (123/456)".
public struct CloneProgress: Equatable, Sendable {
    public let phase: String
    public let percent: Int

    public init(phase: String, percent: Int) {
        self.phase = phase
        self.percent = percent
    }

    private static var line: Regex<(Substring, Substring, Substring)> { /^(?:remote: )?([A-Za-z][A-Za-z ]*?):\s+(\d{1,3})%/ }

    /// The newest progress in a chunk of git's error output (lines end with `\r` while a phase is running).
    public static func latest(in output: String) -> CloneProgress? {
        for piece in output.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).reversed() {
            if let match = piece.firstMatch(of: line), let percent = Int(match.2) {
                return CloneProgress(phase: String(match.1), percent: min(percent, 100))
            }
        }
        return nil
    }
}

/// What a failed contact with a server means for the person waiting.
public enum RemoteFailure: Equatable, Sendable {
    /// Wrong or missing login: ask for one.
    case needsLogin
    /// The server cannot be reached (offline, VPN not connected, slow): wait and try again.
    case unreachable
    case notFound
    case other(String)

    private static let loginSigns = ["could not read Username", "could not read Password", "Authentication failed",
                                     "terminal prompts disabled", "Permission denied (publickey", "HTTP Basic: Access denied",
                                     "Invalid username or password", "The requested URL returned error: 401",
                                     "The requested URL returned error: 403"]
    private static let missingSigns = ["Repository not found", "does not appear to be a git repository",
                                       "The requested URL returned error: 404", "not found"]
    private static let unreachableSigns = ["Could not resolve host", "Could not resolve hostname", "Operation timed out",
                                           "Connection timed out", "Connection refused", "Network is unreachable",
                                           "No route to host", "SSL connect error", "Failed to connect", "Connection reset",
                                           "Connection closed by", "Temporary failure in name resolution", "Host is down"]

    public static func classify(_ error: GitError) -> RemoteFailure {
        switch error {
        case .timedOut:
            return .unreachable
        case .failed(_, _, let stderr):
            if loginSigns.contains(where: { stderr.localizedCaseInsensitiveContains($0) }) { return .needsLogin }
            if unreachableSigns.contains(where: { stderr.localizedCaseInsensitiveContains($0) }) { return .unreachable }
            if missingSigns.contains(where: { stderr.localizedCaseInsensitiveContains($0) }) { return .notFound }
            return .other(stderr)
        default:
            return .other(error.description)
        }
    }
}
