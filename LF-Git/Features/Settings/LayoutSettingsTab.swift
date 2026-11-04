import SwiftUI

/// How the repository window is arranged: the Changes section, the list sections and the Reflog timeline.
struct LayoutSettingsTab: View {
    @AppStorage(LayoutPreferences.changesKey) private var changesRaw = ChangesLayout.default.rawValue
    @AppStorage(LayoutPreferences.listsKey) private var listsRaw = ListsLayout.default.rawValue
    @AppStorage(LayoutPreferences.timelineKey) private var reflogIsTimeline = LayoutPreferences.timelineDefault

    var body: some View {
        SettingsPage {
            SettingsCard("Changes", description: "How the Changes section shows the file list and the diff.") {
                Picker("Changes layout", selection: $changesRaw) {
                    ForEach(ChangesLayout.allCases) { layout in
                        Text(layout.title).tag(layout.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .accessibilityIdentifier("layout-changes-picker")
            }
            SettingsCard("Lists",
                         description: "How the list sections lay out the list and the details. Applies to Branches, History, Stash, Tags and Reflog.") {
                Picker("Lists layout", selection: $listsRaw) {
                    ForEach(ListsLayout.allCases) { layout in
                        Text(layout.title).tag(layout.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .accessibilityIdentifier("layout-lists-picker")
            }
            SettingsCard("Reflog", description: "Show the Reflog as a timeline grouped by day, instead of a plain list.") {
                Toggle("Reflog as a timeline", isOn: $reflogIsTimeline)
                    .accessibilityIdentifier("layout-timeline-toggle")
            }
        }
    }
}

#Preview("Layout") {
    LayoutSettingsTab()
        .frame(width: Chrome.settingsContent, height: 520)
}
