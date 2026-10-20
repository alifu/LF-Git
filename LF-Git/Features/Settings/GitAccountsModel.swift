import Foundation
import LFKit
import Observation

/// Logins for git servers (an internal GitLab behind a VPN, signed in with an LDAP account).
/// The list of servers and usernames is kept in UserDefaults; passwords only ever go to git's credential helper.
@Observable
final class GitAccountsModel {
    var host = ""
    var username = ""
    var password = ""
    private(set) var accounts: [GitAccount] = []
    private(set) var message: String?
    private(set) var isError = false
    private let credentials: GitCredentials
    private let defaults: UserDefaults

    static let storageKey = "gitAccounts"

    init(credentials: GitCredentials = GitCredentials(), defaults: UserDefaults = .standard) {
        self.credentials = credentials
        self.defaults = defaults
        accounts = (defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([GitAccount].self, from: $0) }) ?? []
    }

    var canAdd: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && !username.isEmpty && !password.isEmpty
    }

    func add() {
        if remember(host: host, username: username, password: password) {
            host = ""
            username = ""
            password = ""
        }
    }

    /// Keeps a login in git's credential helper and lists it. False (with `message` set) when that failed.
    @discardableResult
    func remember(host: String, username: String, password: String) -> Bool {
        let account = GitAccount(host: GitCredentials.canonicalHost(Self.normalized(host)), username: username.trimmingCharacters(in: .whitespaces))
        do {
            try credentials.ensureHelper()
            try credentials.save(account, password: password)
            accounts = accounts.filter { $0.id != account.id } + [account]
            persist()
            report("Saved \(account.id) in your git credential helper.")
            return true
        } catch {
            report(error.localizedDescription, isError: true)
            return false
        }
    }

    /// The saved login for a server, to pre-fill a sign-in form.
    func account(forHost host: String) -> GitAccount? {
        let key = GitCredentials.canonicalHost(Self.normalized(host))
        return accounts.first { GitCredentials.canonicalHost($0.host) == key }
    }

    func remove(_ account: GitAccount) {
        do {
            try credentials.remove(account)
            accounts = accounts.filter { $0 != account }
            persist()
            report("Removed \(account.id).")
        } catch {
            report(error.localizedDescription, isError: true)
        }
    }

    /// People paste the address from the browser: keep the host (and port) only.
    static func normalized(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        return text
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: Self.storageKey)
    }

    private func report(_ text: String, isError: Bool = false) {
        message = text
        self.isError = isError
    }
}
