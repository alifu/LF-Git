import Foundation
import LFKit
import Testing
@testable import LF_Git

@MainActor
@Suite("Git accounts model")
struct GitAccountsModelTests {
    private func makeModel() throws -> (GitAccountsModel, URL, UserDefaults) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-accounts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = dir.appendingPathComponent("gitconfig")
        try "[credential]\n\thelper = store --file=\(dir.appendingPathComponent("store").path)\n"
            .write(to: config, atomically: true, encoding: .utf8)
        let defaults = UserDefaults(suiteName: "lfgit-test-\(UUID().uuidString)")!
        return (GitAccountsModel(credentials: GitCredentials(configFile: config), defaults: defaults), dir, defaults)
    }

    @Test("adding an account keeps the login, clears the password field and remembers the server")
    func adds() throws {
        let (model, dir, defaults) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        model.host = "https://gitlab.corp.example/group/project.git"
        model.username = "ada"
        model.password = "pw"
        #expect(model.canAdd)
        model.add()

        #expect(!model.isError)
        #expect(model.accounts == [GitAccount(host: "gitlab.corp.example", username: "ada")])
        #expect(model.password.isEmpty)
        let reloaded = GitAccountsModel(credentials: GitCredentials(), defaults: defaults)
        #expect(reloaded.accounts == model.accounts)
        let stored = try String(contentsOf: dir.appendingPathComponent("store"), encoding: .utf8)
        #expect(stored.contains("gitlab.corp.example"))
        #expect(defaults.data(forKey: GitAccountsModel.storageKey).map { !String(decoding: $0, as: UTF8.self).contains("pw\"") } == true)
    }

    @Test("removing an account forgets it")
    func removes() throws {
        let (model, dir, _) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        model.host = "gitlab.corp.example"
        model.username = "ada"
        model.password = "pw"
        model.add()
        model.remove(model.accounts[0])
        #expect(model.accounts.isEmpty)
        let stored = try String(contentsOf: dir.appendingPathComponent("store"), encoding: .utf8)
        #expect(!stored.contains("gitlab.corp.example"))
    }

    @Test("a bad server name is reported and nothing is saved")
    func rejects() throws {
        let (model, dir, _) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        model.host = "bad host name"
        model.username = "ada"
        model.password = "pw"
        model.add()
        #expect(model.isError)
        #expect(model.accounts.isEmpty)
    }
}
