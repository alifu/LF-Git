import Foundation

/// A login for one git server, such as an internal GitLab that signs in with a company (LDAP) account.
/// Only the non-secret parts live here; the password goes straight to git's credential helper.
public struct GitAccount: Equatable, Hashable, Sendable, Codable, Identifiable {
    /// Host name, with `:port` when the server does not use 443.
    public var host: String
    public var username: String

    public var id: String { "\(username)@\(host)" }

    public init(host: String, username: String) {
        self.host = host
        self.username = username
    }
}

/// Stores logins through the user's own `credential.helper` (the macOS keychain by default), so the terminal,
/// the app and every git command share them. The app never keeps a password itself.
public struct GitCredentials: Sendable {
    public enum Problem: Error, Equatable, LocalizedError, Sendable {
        case invalidHost
        case invalidUsername
        case invalidPassword
        case helperFailed

        public var errorDescription: String? {
            switch self {
            case .invalidHost: "Enter the server name only, such as gitlab.company.com (no https:// or path)."
            case .invalidUsername: "Enter the username on one line."
            case .invalidPassword: "Enter the password on one line."
            case .helperFailed: "git's credential helper could not store or remove the login. Check `git config credential.helper`."
            }
        }
    }

    private let configFile: URL?
    /// `https` for every GitLab behind a VPN worth using; `http` only if the server offers nothing else.
    private static let scheme = "https"
    private static let defaultHelper = "osxkeychain"

    /// - Parameter configFile: a file to use instead of `~/.gitconfig` (for tests).
    public init(configFile: URL? = nil) {
        self.configFile = configFile
    }

    var environment: [String: String] {
        configFile.map { ["GIT_CONFIG_GLOBAL": $0.path] } ?? [:]
    }

    /// Saves (or replaces) the password for this account.
    public func save(_ account: GitAccount, password: String) throws {
        let account = try Self.validate(account)
        guard !password.isEmpty, Self.isSingleLine(password) else { throw Problem.invalidPassword }
        try send("approve", "protocol=\(Self.scheme)\nhost=\(account.host)\nusername=\(account.username)\npassword=\(password)\n\n")
    }

    /// Forgets the password for this account.
    public func remove(_ account: GitAccount) throws {
        let account = try Self.validate(account)
        try send("reject", "protocol=\(Self.scheme)\nhost=\(account.host)\nusername=\(account.username)\n\n")
    }

    /// The helpers git will use (system, global and local configuration); empty when git has nowhere to keep a password.
    public func helper() throws(GitError) -> [String] {
        let result = try Git(directory: FileManager.default.temporaryDirectory)
            .run(["config", "--get-all", "credential.helper"], environment: environment, allowedStatuses: [0, 1])
        return result.text.split(separator: "\n").map(String.init)
    }

    /// Sets the keychain helper when no helper exists, so a saved password is actually kept.
    public func ensureHelper() throws(GitError) {
        guard try helper().isEmpty else { return }
        try Git(directory: FileManager.default.temporaryDirectory)
            .run(["config", "--global", "credential.helper", Self.defaultHelper], environment: environment)
    }

    private func send(_ verb: String, _ input: String) throws {
        // The password travels through git's standard input, never through arguments or the command log.
        do {
            try Git(directory: FileManager.default.temporaryDirectory)
                .run(["credential", verb], stdin: Data(input.utf8), environment: environment)
        } catch {
            // The helper's own error text is not shown: a custom helper could echo what it was given.
            throw Problem.helperFailed
        }
    }

    /// The key git itself looks up: lower-case host, and no `:443` (the default port for https).
    public static func canonicalHost(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasSuffix(":443") ? String(lower.dropLast(4)) : lower
    }

    private static func validate(_ account: GitAccount) throws -> GitAccount {
        let hostPattern = #/^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?$/#
        let host = canonicalHost(account.host)
        guard host.wholeMatch(of: hostPattern) != nil else { throw Problem.invalidHost }
        if let port = host.split(separator: ":").dropFirst().first.flatMap({ Int($0) }), !(1...65535).contains(port) {
            throw Problem.invalidHost
        }
        guard !account.username.isEmpty, isSingleLine(account.username) else { throw Problem.invalidUsername }
        return GitAccount(host: host, username: account.username)
    }

    /// A line break would let a value add fields of its own to git's credential protocol.
    private static func isSingleLine(_ value: String) -> Bool {
        !value.contains { $0.isNewline || $0 == "\0" }
    }
}
