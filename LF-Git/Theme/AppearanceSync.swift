import SwiftUI

/// Keeps `NSApp.appearance` in sync with the stored setting from any scene,
/// so a change made in Settings applies even when no main window is open.
private struct AppearanceSync: ViewModifier {
    @AppStorage(AppearanceSetting.storageKey) private var appearanceRaw = AppearanceSetting.system.rawValue

    func body(content: Content) -> some View {
        content
            .onAppear(perform: apply)
            .onChange(of: appearanceRaw) { apply() }
    }

    private func apply() {
        AppearanceSetting(storedValue: appearanceRaw).apply()
    }
}

extension View {
    func syncsAppearance() -> some View {
        modifier(AppearanceSync())
    }
}
