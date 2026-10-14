import LFKit
import SwiftUI

@main
struct LF_GitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()

    var body: some Scene {
        Window("LF-Git", id: "main") {
            ContentView(app: app)
                .syncsAccent()
                .syncsAppearance()
                .onAppear {
                    GitDiffFile.sweepStaleTemporaryFiles()
                    Task { await TerminalEnvironment.shared.reload() }
                    delegate.app = app
                    app.applyLaunchArgumentsOnce(CommandLine.arguments)
                }
                .onOpenURL { app.handle($0) }
        }
        .defaultSize(width: 1200, height: 800)
        .handlesExternalEvents(matching: ["lfgit"])
        .commands { AppCommands(app: app) }

        Settings {
            SettingsView()
                .syncsAccent(rebuilds: false)
                .syncsAppearance()
        }
    }
}
