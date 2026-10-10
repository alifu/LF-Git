import Foundation
import LFKit
import Observation

/// Edits the global git identity and SSL choice; nothing is written until `save()`.
@Observable
final class GitSettingsModel {
    var name = ""
    var email = ""
    var verifiesSSL = true
    private(set) var message: String?
    private(set) var isError = false
    private let configFile: URL?
    private var saved: GitUserSettings?

    init(configFile: URL? = nil) {
        self.configFile = configFile
    }

    var hasChanges: Bool { saved != current }

    private var current: GitUserSettings {
        GitUserSettings(name: name, email: email, verifiesSSL: verifiesSSL)
    }

    func load() {
        do {
            let settings = try GitUserSettings.load(configFile: configFile)
            name = settings.name
            email = settings.email
            verifiesSSL = settings.verifiesSSL
            saved = settings
            message = nil
        } catch {
            report(error)
        }
    }

    func save() {
        do {
            try current.save(configFile: configFile)
            saved = current
            message = "Saved to ~/.gitconfig"
            isError = false
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        message = error.localizedDescription
        isError = true
    }
}
