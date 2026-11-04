import Testing
@testable import LF_Git

@MainActor
@Suite("Settings sidebar")
struct SettingsLayoutTests {
    @Test("the sidebar lists every tab exactly once, in the order the window shows them")
    func sidebarOrderListsEveryTabOnce() {
        let order = SettingsTab.sidebarOrder

        #expect(order == [.general, .account, .network, .environment, .theme, .layout])
        #expect(Set(order) == Set(SettingsTab.allCases))
        #expect(Set(order).count == order.count)
    }

    @Test("every tab has a non-empty title and symbol", arguments: SettingsTab.allCases)
    func everyTabHasTitleAndSymbol(tab: SettingsTab) {
        #expect(!tab.title.isEmpty)
        #expect(!tab.symbol.isEmpty)
    }

    @Test("the Layout tab uses the rectangle.3.group symbol")
    func layoutTabSymbol() {
        #expect(SettingsTab.layout.symbol == "rectangle.3.group")
    }

    @Test("a stored tab name reads back as the same tab", arguments: SettingsTab.allCases)
    func storedTabRoundTrip(tab: SettingsTab) {
        #expect(SettingsTab(stored: tab.rawValue) == tab)
    }

    @Test("an unknown or missing stored tab opens General")
    func unknownTabFallsBackToGeneral() {
        #expect(SettingsTab(stored: "gone-tab") == .general)
        #expect(SettingsTab(stored: "") == .general)
        #expect(SettingsTab(stored: nil) == .general)
    }
}
