import Foundation
import Testing
@testable import LF_Git

@Suite("Layout preferences")
struct LayoutPreferencesTests {
    @Test("Classic is the default for every area, so nothing moves until a layout is picked")
    func defaults() {
        #expect(ChangesLayout.default == .classic)
        #expect(ListsLayout.default == .classic)
        #expect(LayoutPreferences.timelineDefault == false)
    }

    @Test("a stored value reads back as the same layout", arguments: ChangesLayout.allCases)
    func changesRoundTrip(layout: ChangesLayout) {
        #expect(ChangesLayout(stored: layout.rawValue) == layout)
    }

    @Test("a stored value reads back as the same list layout", arguments: ListsLayout.allCases)
    func listsRoundTrip(layout: ListsLayout) {
        #expect(ListsLayout(stored: layout.rawValue) == layout)
    }

    @Test("an unknown or missing stored value falls back to Classic")
    func unknownFallsBack() {
        #expect(ChangesLayout(stored: "floating-islands") == .classic)
        #expect(ChangesLayout(stored: nil) == .classic)
        #expect(ListsLayout(stored: "") == .classic)
    }

    @Test("every layout has a title for the Settings picker")
    func titles() {
        #expect(ChangesLayout.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(ListsLayout.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test("the storage keys are distinct")
    func keys() {
        let keys = [LayoutPreferences.changesKey, LayoutPreferences.listsKey, LayoutPreferences.timelineKey]
        #expect(Set(keys).count == keys.count)
    }
}
