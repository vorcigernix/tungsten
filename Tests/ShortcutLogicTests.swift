import AppKit
import Foundation

@main
struct ShortcutLogicTests {
    static func main() throws {
        try testCatalogIncludesAvailableAndComingSoonActions()
        try testCEFBackedActionsAreAvailable()
        try testOverridesReplaceDefaultsAndResetRestoresDefaults()
        try testClearedBindingLeavesActionUnassigned()
        try testDuplicateActiveBindingsAreDetected()
        try testComingSoonDefaultsDoNotBlockRemapping()
        try testComingSoonActionDoesNotDispatch()
        try testModifierOrderDoesNotAffectMatching()
        print("ShortcutLogicTests passed")
    }

    static func testCatalogIncludesAvailableAndComingSoonActions() throws {
        let actions = ShortcutCatalog.actions

        try expect(actions.contains { $0.id == .newTab && $0.availability == .available })
        try expect(actions.contains { $0.id == .viewHistory && $0.availability == .comingSoon })
        try expect(actions.contains { $0.title == "Open Little Arc" } == false)
        try expect(actions.contains { $0.title.contains("Space") } == false)
        try expect(actions.contains { $0.title.contains("Split View") } == false)
    }

    static func testCEFBackedActionsAreAvailable() throws {
        let manager = ShortcutManager(store: makeStore("cef-backed"))

        try expect(ShortcutCatalog.action(id: .zoomIn)?.availability == .available)
        try expect(ShortcutCatalog.action(id: .zoomOut)?.availability == .available)
        try expect(ShortcutCatalog.action(id: .resetZoom)?.availability == .available)
        try expect(ShortcutCatalog.action(id: .findInPage)?.availability == .available)
        try expect(manager.dispatchableAction(for: ShortcutBinding(key: "f", modifiers: [.command]))?.id == .findInPage)
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

    static func testComingSoonDefaultsDoNotBlockRemapping() throws {
        let manager = ShortcutManager(store: makeStore("coming-soon-remap"))
        let historyDefault = ShortcutBinding(key: "y", modifiers: [.command])

        try expect(manager.conflicts(for: historyDefault, excluding: .newTab).isEmpty)
        try expect(manager.setCustomBinding(historyDefault, for: .newTab) == .assigned)
        try expect(manager.dispatchableAction(for: historyDefault)?.id == .newTab)
    }

    static func testComingSoonActionDoesNotDispatch() throws {
        let manager = ShortcutManager(store: makeStore("coming-soon"))

        try expect(manager.dispatchableAction(for: ShortcutBinding(key: "y", modifiers: [.command])) == nil)
        try expect(manager.dispatchableAction(for: ShortcutBinding(key: "t", modifiers: [.command]))?.id == .newTab)
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
