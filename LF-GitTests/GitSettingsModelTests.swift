import Foundation
import Testing
@testable import LF_Git

@MainActor
@Suite("Git settings model")
struct GitSettingsModelTests {
    private func makeModel() -> (GitSettingsModel, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lfgit-settings-\(UUID().uuidString)")
        return (GitSettingsModel(configFile: file), file)
    }

    @Test("saving writes the identity and SSL choice, and the form is clean afterwards")
    func saves() {
        let (model, file) = makeModel()
        defer { try? FileManager.default.removeItem(at: file) }
        model.load()
        #expect(!model.hasChanges)

        model.name = "Ada"
        model.email = "ada@example.com"
        model.verifiesSSL = false
        #expect(model.hasChanges)
        model.save()

        #expect(!model.hasChanges)
        #expect(!model.isError)
        let reloaded = GitSettingsModel(configFile: file)
        reloaded.load()
        #expect(reloaded.name == "Ada")
        #expect(reloaded.email == "ada@example.com")
        #expect(!reloaded.verifiesSSL)
    }

    @Test("an invalid email shows an error and keeps the form dirty")
    func rejects() {
        let (model, file) = makeModel()
        defer { try? FileManager.default.removeItem(at: file) }
        model.load()
        model.email = "nope"
        model.save()
        #expect(model.isError)
        #expect(model.hasChanges)
    }
}
