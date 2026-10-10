import Foundation
import LFKit
import LFTestSupport
import Testing

@Suite("Git user settings")
struct GitUserSettingsTests {
    private func configFile() -> (Sandbox, URL) {
        let sandbox = Sandbox()
        return (sandbox, sandbox.root.appendingPathComponent("gitconfig"))
    }

    @Test("an empty configuration loads as no identity and SSL verification on")
    func defaults() throws {
        let (sandbox, file) = configFile()
        let settings = try GitUserSettings.load(configFile: file)
        #expect(settings == GitUserSettings(name: "", email: "", verifiesSSL: true))
        withExtendedLifetime(sandbox) {}
    }

    @Test("name, email and SSL choice survive a save and load")
    func roundTrip() throws {
        let (sandbox, file) = configFile()
        let saved = GitUserSettings(name: "Ada Lovelace", email: "ada@example.com", verifiesSSL: false)
        try saved.save(configFile: file)
        #expect(try GitUserSettings.load(configFile: file) == saved)
        #expect(try String(contentsOf: file, encoding: .utf8).contains("sslVerify = false"))
        withExtendedLifetime(sandbox) {}
    }

    @Test("turning verification back on and clearing the identity removes the entries")
    func clears() throws {
        let (sandbox, file) = configFile()
        try GitUserSettings(name: "Ada", email: "ada@example.com", verifiesSSL: false).save(configFile: file)
        try GitUserSettings(name: "", email: "", verifiesSSL: true).save(configFile: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("name"))
        #expect(!text.contains("email"))
        #expect(!text.contains("sslVerify"))
        withExtendedLifetime(sandbox) {}
    }

    @Test("invalid values are rejected and leave the file untouched")
    func validation() throws {
        let (sandbox, file) = configFile()
        #expect(throws: GitUserSettings.Problem.invalidEmail) {
            try GitUserSettings(name: "Ada", email: "not-an-email", verifiesSSL: true).save(configFile: file)
        }
        #expect(throws: GitUserSettings.Problem.multiline) {
            try GitUserSettings(name: "Ada\nEvil", email: "", verifiesSSL: true).save(configFile: file)
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        withExtendedLifetime(sandbox) {}
    }

    @Test("a name that looks like an option is stored as a name")
    func optionLikeName() throws {
        let (sandbox, file) = configFile()
        let saved = GitUserSettings(name: "--global", email: "", verifiesSSL: true)
        try saved.save(configFile: file)
        #expect(try GitUserSettings.load(configFile: file).name == "--global")
        withExtendedLifetime(sandbox) {}
    }
}
