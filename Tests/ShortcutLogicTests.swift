import AppKit
import Foundation

@main
struct ShortcutLogicTests {
    static func main() throws {
        try testCatalogIncludesAvailableAndComingSoonActions()
        try testThreadFirstActionLabels()
        try testCEFBackedActionsAreAvailable()
        try testRemainingBrowserActionsAreAvailable()
        try testOverridesReplaceDefaultsAndResetRestoresDefaults()
        try testClearedBindingLeavesActionUnassigned()
        try testDuplicateActiveBindingsAreDetected()
        try testRemainingBrowserActionDefaultsParticipateInRemapping()
        try testModifierOrderDoesNotAffectMatching()
        print("ShortcutLogicTests passed")
    }

    static func testCatalogIncludesAvailableAndComingSoonActions() throws {
        let actions = ShortcutCatalog.actions

        try expect(actions.contains { $0.id == .newTab && $0.availability == .available })
        try expect(actions.allSatisfy(\.isAvailable))
        try expect(actions.contains { $0.title == "Open Little Arc" } == false)
        try expect(actions.contains { $0.title.contains("Space") } == false)
        try expect(actions.contains { $0.title.contains("Split View") } == false)
    }

    static func testThreadFirstActionLabels() throws {
        try expect(ShortcutCatalog.action(id: .newTab)?.title == "New Thread")
        try expect(ShortcutCatalog.action(id: .closeCurrentTab)?.title == "Close Current Thread")
        try expect(ShortcutCatalog.action(id: .reopenLastClosedTab)?.title == "Re-open Last Closed Thread")
        try expect(ShortcutCatalog.action(id: .pinOrUnpinCurrentTab)?.title == "Pin or Unpin Current Thread")
        try expect(ShortcutCatalog.action(id: .focusAddressInput)?.title == "Ask or Open URL")
        try expect(ShortcutCatalog.action(id: .clearUnpinnedTabs)?.title == "Clear Unpinned Threads")
        try expect(ShortcutCatalog.action(id: .selectTab1)?.title == "Go to Thread 1")
        try expect(ShortcutCatalog.action(id: .selectPreviousTab)?.title == "Previous Thread")
        try expect(ShortcutCatalog.action(id: .selectNextTab)?.title == "Next Thread")
    }

    static func testCEFBackedActionsAreAvailable() throws {
        let manager = ShortcutManager(store: makeStore("cef-backed"))

        try expect(ShortcutCatalog.action(id: .zoomIn)?.availability == .available)
        try expect(ShortcutCatalog.action(id: .zoomOut)?.availability == .available)
        try expect(ShortcutCatalog.action(id: .resetZoom)?.availability == .available)
        try expect(ShortcutCatalog.action(id: .findInPage)?.availability == .available)
        try expect(manager.dispatchableAction(for: ShortcutBinding(key: "f", modifiers: [.command]))?.id == .findInPage)
    }

    static func testRemainingBrowserActionsAreAvailable() throws {
        let manager = ShortcutManager(store: makeStore("remaining-browser-actions"))

        let expected: [(ShortcutActionID, ShortcutBinding)] = [
            (.newWindow, ShortcutBinding(key: "n", modifiers: [.command])),
            (.newIncognitoWindow, ShortcutBinding(key: "n", modifiers: [.command, .shift])),
            (.reopenLastClosedTab, ShortcutBinding(key: "t", modifiers: [.command, .shift])),
            (.pinOrUnpinCurrentTab, ShortcutBinding(key: "d", modifiers: [.command])),
            (.clearUnpinnedTabs, ShortcutBinding(key: "k", modifiers: [.command, .shift])),
            (.viewHistory, ShortcutBinding(key: "y", modifiers: [.command]))
        ]

        for (actionID, binding) in expected {
            try expect(ShortcutCatalog.action(id: actionID)?.availability == .available)
            try expect(manager.dispatchableAction(for: binding)?.id == actionID)
        }
    }

    static func testOverridesReplaceDefaultsAndResetRestoresDefaults() throws {
        let manager = ShortcutManager(store: makeStore("override"))
        let defaultBinding = ShortcutBinding(key: "t", modifiers: [.command])
        let customBinding = ShortcutBinding(key: "n", modifiers: [.command, .option])

        try expect(manager.activeBindings(for: .newTab) == [defaultBinding])
        try expect(manager.setCustomBinding(customBinding, for: .newTab) == .assigned)
        try expect(manager.activeBindings(for: .newTab) == [customBinding])

        manager.resetBinding(for: .newTab)
        try expect(manager.activeBindings(for: .newTab) == [defaultBinding])
    }

    static func testClearedBindingLeavesActionUnassigned() throws {
        let manager = ShortcutManager(store: makeStore("clear"))

        manager.clearBinding(for: .newTab)
        try expect(manager.activeBindings(for: .newTab).isEmpty)

        manager.resetBinding(for: .newTab)
        try expect(manager.activeBindings(for: .newTab) == [ShortcutBinding(key: "t", modifiers: [.command])])
    }

    static func testDuplicateActiveBindingsAreDetected() throws {
        let manager = ShortcutManager(store: makeStore("duplicate"))
        let closeTab = ShortcutBinding(key: "w", modifiers: [.command])

        let conflicts = manager.conflicts(for: closeTab, excluding: .newTab)
        try expect(conflicts.map(\.id) == [.closeCurrentTab])
        try expect(manager.setCustomBinding(closeTab, for: .newTab) == .conflict(existingAction: .closeCurrentTab))
    }

    static func testRemainingBrowserActionDefaultsParticipateInRemapping() throws {
        let manager = ShortcutManager(store: makeStore("remaining-browser-remap"))
        let historyDefault = ShortcutBinding(key: "y", modifiers: [.command])

        let conflicts = manager.conflicts(for: historyDefault, excluding: .newTab)
        try expect(conflicts.map(\.id) == [.viewHistory])
        try expect(manager.setCustomBinding(historyDefault, for: .newTab) == .conflict(existingAction: .viewHistory))
        manager.clearBinding(for: .viewHistory)
        try expect(manager.setCustomBinding(historyDefault, for: .newTab) == .assigned)
        try expect(manager.activeBindings(for: .newTab) == [historyDefault])
        try expect(manager.dispatchableAction(for: ShortcutBinding(key: "t", modifiers: [.command])) == nil)
    }

    static func testModifierOrderDoesNotAffectMatching() throws {
        let first = ShortcutBinding(key: "T", modifiers: [.shift, .command])
        let second = ShortcutBinding(key: "t", modifiers: [.command, .shift])
        let zoomIn = ShortcutBinding(key: "+", modifiers: [.command, .shift])
        let shiftedEquals = ShortcutBinding(key: "=", modifiers: [.command, .shift])

        try expect(first == second)
        try expect(first.displayString == "Command-Shift-T")
        try expect(zoomIn == ShortcutBinding(key: "+", modifiers: [.command]))
        try expect(shiftedEquals == ShortcutBinding(key: "+", modifiers: [.command]))
    }

    static func makeStore(_ name: String) -> ShortcutPreferencesStore {
        let suiteName = "TungstenShortcutTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ShortcutPreferencesStore(userDefaults: defaults, key: "ShortcutOverrides")
    }

    static func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        if condition() == false {
            throw TestFailure(file: "\(file)", line: line)
        }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let file: String
    let line: UInt

    var description: String {
        "Expectation failed at \(file):\(line)"
    }
}
