import AppKit
import Foundation

@main
struct ShortcutLogicTests {
    static func main() throws {
        try testCatalogIncludesAvailableAndComingSoonActions()
        try testTabFirstActionLabels()
        try testCEFBackedActionsAreAvailable()
        try testPrivateAndTorTabActionsAreAvailable()
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

    static func testTabFirstActionLabels() throws {
        let expectedLabels: [(ShortcutActionID, String)] = [
            (.newTab, "New Tab"),
            (.closeCurrentTab, "Close Current Tab"),
            (.reopenLastClosedTab, "Re-open Last Closed Tab"),
            (.pinOrUnpinCurrentTab, "Pin or Unpin Current Tab"),
            (.focusAddressInput, "Search or Open URL"),
            (.clearUnpinnedTabs, "Clear Unpinned Tabs"),
            (.selectTab1, "Go to Tab 1"),
            (.selectTab2, "Go to Tab 2"),
            (.selectTab3, "Go to Tab 3"),
            (.selectTab4, "Go to Tab 4"),
            (.selectTab5, "Go to Tab 5"),
            (.selectTab6, "Go to Tab 6"),
            (.selectTab7, "Go to Tab 7"),
            (.selectTab8, "Go to Tab 8"),
            (.selectTab9, "Go to Tab 9"),
            (.selectRecentTab, "Toggle Recent Tabs"),
            (.selectPreviousTab, "Previous Tab"),
            (.selectNextTab, "Next Tab")
        ]

        for (actionID, title) in expectedLabels {
            try expect(ShortcutCatalog.action(id: actionID)?.title == title)
        }
    }

    static func testCEFBackedActionsAreAvailable() throws {
        let manager = ShortcutManager(store: makeStore("cef-backed"))

        try expect(ShortcutCatalog.action(id: .zoomIn)?.availability == .available)
        try expect(ShortcutCatalog.action(id: .zoomOut)?.availability == .available)
        try expect(ShortcutCatalog.action(id: .resetZoom)?.availability == .available)
        try expect(ShortcutCatalog.action(id: .findInPage)?.availability == .available)
        try expect(manager.dispatchableAction(for: ShortcutBinding(key: "f", modifiers: [.command]))?.id == .findInPage)
    }

    static func testPrivateAndTorTabActionsAreAvailable() throws {
        let manager = ShortcutManager(store: makeStore("private-tor-tabs"))

        let expected: [(ShortcutActionID, String, ShortcutBinding)] = [
            (.newIncognitoTab, "New Incognito Tab", ShortcutBinding(key: "n", modifiers: [.command, .option])),
            (.newTorTab, "New Tor Tab", ShortcutBinding(key: "t", modifiers: [.command, .option]))
        ]

        for (actionID, title, binding) in expected {
            try expect(ShortcutCatalog.action(id: actionID)?.title == title)
            try expect(ShortcutCatalog.action(id: actionID)?.availability == .available)
            try expect(manager.dispatchableAction(for: binding)?.id == actionID)
        }
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
        let customBinding = ShortcutBinding(key: "m", modifiers: [.command, .option])

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
