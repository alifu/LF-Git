import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git credentials")
struct GitCredentialsTests {
    /// A global config whose credential helper is a plain file inside the sandbox, never the real keychain.
    private func environment() throws -> (Sandbox, GitCredentials, Git) {
        let sandbox = Sandbox()
        let config = sandbox.root.appendingPathComponent("gitconfig")
        let store = sandbox.root.appendingPathComponent("credentials")
        try "[credential]\n\thelper = store --file=\(store.path)\n".write(to: config, atomically: true, encoding: .utf8)
        let credentials = GitCredentials(configFile: config)
        return (sandbox, credentials, Git(directory: sandbox.root))
    }

    private func lookup(_ git: Git, _ sandbox: Sandbox, host: String, user: String) throws -> String {
        let result = try git.run(["credential", "fill"], stdin: Data("protocol=https\nhost=\(host)\nusername=\(user)\n\n".utf8),
                                 environment: ["GIT_CONFIG_GLOBAL": sandbox.root.appendingPathComponent("gitconfig").path])
        return result.text
    }

    @Test("a saved LDAP login is handed back by git for that host")
    func saveAndFind() throws {
        let (sandbox, credentials, git) = try environment()
        try credentials.save(GitAccount(host: "gitlab.corp.example", username: "ada"), password: "s3cret pass")
        let answer = try lookup(git, sandbox, host: "gitlab.corp.example", user: "ada")
        #expect(answer.contains("password=s3cret pass"))
        withExtendedLifetime(sandbox) {}
    }

    @Test("removing a login makes git forget it")
    func remove() throws {
        let (sandbox, credentials, git) = try environment()
        let account = GitAccount(host: "gitlab.corp.example:8443", username: "ada")
        try credentials.save(account, password: "pw")
        try credentials.remove(account)
        #expect(throws: GitError.self) { _ = try lookup(git, sandbox, host: account.host, user: "ada") }
        withExtendedLifetime(sandbox) {}
    }

    @Test("values that could smuggle extra credential lines are refused")
    func rejectsInjection() throws {
        let (sandbox, credentials, _) = try environment()
        #expect(throws: GitCredentials.Problem.self) {
            try credentials.save(GitAccount(host: "gitlab.example", username: "ada\nhost=evil.example"), password: "pw")
        }
        #expect(throws: GitCredentials.Problem.self) {
            try credentials.save(GitAccount(host: "gitlab.example", username: "ada"), password: "pw\npassword=x")
        }
        #expect(throws: GitCredentials.Problem.self) {
            try credentials.save(GitAccount(host: "https://gitlab.example/", username: "ada"), password: "pw")
        }
        #expect(throws: GitCredentials.Problem.self) {
            try credentials.save(GitAccount(host: "gitlab.example", username: "ada"), password: "")
        }
        withExtendedLifetime(sandbox) {}
    }

    @Test("host case and the default port do not change which login git finds")
    func canonicalHost() throws {
        let (sandbox, credentials, git) = try environment()
        try credentials.save(GitAccount(host: "GitLab.Corp.Example:443", username: "ada"), password: "pw")
        #expect(try lookup(git, sandbox, host: "gitlab.corp.example", user: "ada").contains("password=pw"))
        #expect(throws: GitCredentials.Problem.self) {
            try credentials.save(GitAccount(host: "gitlab.example:70000", username: "ada"), password: "pw")
        }
        withExtendedLifetime(sandbox) {}
    }

    @Test("a helper is configured only when none exists")
    func helper() throws {
        let sandbox = Sandbox()
        let config = sandbox.root.appendingPathComponent("gitconfig")
        let credentials = GitCredentials(configFile: config)
        #expect(try credentials.helper().isEmpty)
        try credentials.ensureHelper()
        #expect(try credentials.helper() == ["osxkeychain"])
        try credentials.ensureHelper()
        #expect(try credentials.helper() == ["osxkeychain"])
    }
}
