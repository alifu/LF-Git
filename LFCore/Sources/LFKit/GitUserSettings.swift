import Foundation

/// The settings every commit and network command depends on, kept in git's own global configuration
/// (`~/.gitconfig`), so the terminal and the app always agree.
public struct GitUserSettings: Equatable, Sendable {
    public var name: String
    public var email: String
    /// `http.sslVerify`: check the server certificate of https remotes. Only switch off for a server you trust.
    public var verifiesSSL: Bool

    public init(name: String, email: String, verifiesSSL: Bool) {
        self.name = name
        self.email = email
        self.verifiesSSL = verifiesSSL
    }

    public enum Problem: Error, Equatable, LocalizedError, Sendable {
        case multiline
        case invalidEmail

        public var errorDescription: String? {
            switch self {
            case .multiline: "Name and email must be a single line."
            case .invalidEmail: "The email address must look like name@example.com."
            }
        }
    }

    private static let nameKey = "user.name"
    private static let emailKey = "user.email"
    private static let sslKey = "http.sslVerify"

    /// - Parameter configFile: a file to use instead of `~/.gitconfig` (for tests).
    public static func load(configFile: URL? = nil) throws(GitError) -> GitUserSettings {
        let git = makeGit()
        let environment = Self.environment(configFile)
        func value(_ key: String) throws(GitError) -> String {
            try git.run(["config", "--global", "--get", key], environment: environment, allowedStatuses: [0, 1]).text
        }
        let ssl = try value(sslKey).lowercased()
        return GitUserSettings(name: try value(nameKey), email: try value(emailKey),
                               verifiesSSL: !["false", "no", "off", "0"].contains(ssl))
    }

    /// Writes the settings globally. Empty name or email, and verification left on, remove the entry so git's
    /// defaults apply again.
    public func save(configFile: URL? = nil) throws {
        let name = name.trimmingCharacters(in: .whitespaces)
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !name.contains(where: \.isNewline), !email.contains(where: \.isNewline) else { throw Problem.multiline }
        guard email.isEmpty || (email.contains("@") && !email.contains(" ")) else { throw Problem.invalidEmail }

        let git = Self.makeGit()
        let environment = Self.environment(configFile)
        func set(_ key: String, _ value: String?) throws {
            if let value {
                try git.run(["config", "--global", key, value], environment: environment)
            } else {
                // Status 5: the key was not set, which is what we wanted.
                try git.run(["config", "--global", "--unset-all", key], environment: environment, allowedStatuses: [0, 5])
            }
        }
        try set(Self.nameKey, name.isEmpty ? nil : name)
        try set(Self.emailKey, email.isEmpty ? nil : email)
        try set(Self.sslKey, verifiesSSL ? nil : "false")
    }

    private static func makeGit() -> Git {
        Git(directory: FileManager.default.temporaryDirectory)
    }

    private static func environment(_ configFile: URL?) -> [String: String] {
        configFile.map { ["GIT_CONFIG_GLOBAL": $0.path] } ?? [:]
    }
}
