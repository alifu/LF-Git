import SwiftUI

struct SettingsView: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearanceRaw = AppearanceSetting.system.rawValue

    var body: some View {
        Form {
            Picker("Appearance", selection: appearance) {
                ForEach(AppearanceSetting.allCases) { setting in
                    Text(setting.title).tag(setting)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var appearance: Binding<AppearanceSetting> {
        Binding(
            get: { AppearanceSetting(storedValue: appearanceRaw) },
            set: { appearanceRaw = $0.rawValue }
        )
    }
}

#Preview("Light") {
    SettingsView().preferredColorScheme(.light)
}

#Preview("Dark") {
    SettingsView().preferredColorScheme(.dark)
}
