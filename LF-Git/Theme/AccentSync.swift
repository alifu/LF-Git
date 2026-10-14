import SwiftUI

/// Re-draws a window when the accent color is changed in Settings.
///
/// Views read colors through `.theme(_:)`, which looks the choice up when a view is built, so a window whose
/// content has not changed would keep the old accent. A new identity makes SwiftUI (and the AppKit tables inside it)
/// build everything again with the new color; models live outside the views, so no work is lost, only transient
/// view state such as which folders are open.
private struct AccentSync: ViewModifier {
    @AppStorage(AccentSetting.storageKey) private var accentRaw = LFAccentChoice.green.rawValue
    /// False for a window that keeps edits in its own state (Settings): it only gets the new tint.
    let rebuilds: Bool

    func body(content: Content) -> some View {
        content
            .tint(.theme(.accent))
            .id(rebuilds ? accentRaw : "")
    }
}

extension View {
    func syncsAccent(rebuilds: Bool = true) -> some View {
        modifier(AccentSync(rebuilds: rebuilds))
    }
}
