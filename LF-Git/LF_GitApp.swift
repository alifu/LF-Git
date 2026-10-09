import SwiftUI

@main
struct LF_GitApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.theme(.accent))
                .syncsAppearance()
        }

        Settings {
            SettingsView()
                .tint(.theme(.accent))
                .syncsAppearance()
        }
    }
}
