import Foundation

enum ShortcutCategory: String, CaseIterable, Codable {
    case everyday = "Everyday Use"
    case quickNavigation = "Quick Navigation"
    case other = "Other"
}

enum ShortcutAvailability: String, Codable {
    case available
    case comingSoon
}

enum ShortcutActionID: String, CaseIterable, Codable, Hashable {
    case newTab
    case newWindow
    case newIncognitoWindow
    case closeCurrentTab
    case reopenLastClosedTab
    case pinOrUnpinCurrentTab
    case copyCurrentURL
    case copyCurrentURLAsMarkdown
    case focusAddressInput
    case toggleSidebar
    case clearUnpinnedTabs
    case selectTab1
    case selectTab2
    case selectTab3
    case selectTab4
    case selectTab5
    case selectTab6
    case selectTab7
    case selectTab8
    case selectTab9
    case selectRecentTab
    case selectPreviousTab
    case selectNextTab
    case goBack
    case goForward
    case reloadOrStopLoading
    case viewHistory
    case zoomIn
    case zoomOut
    case resetZoom
    case findInPage
}

struct ShortcutAction: Identifiable, Codable, Equatable {
    typealias ID = ShortcutActionID

    let id: ShortcutActionID
    let title: String
    let category: ShortcutCategory
    let defaultBindings: [ShortcutBinding]
    let availability: ShortcutAvailability

    var isAvailable: Bool {
        availability == .available
    }
}

enum ShortcutCatalog {
    static let actions: [ShortcutAction] = everydayActions + quickNavigationActions + otherActions

    static func action(id: ShortcutActionID) -> ShortcutAction? {
        actions.first { $0.id == id }
    }

    private static let everydayActions: [ShortcutAction] = [
        available(.newTab, "New Tab", .everyday, [.cmd("t")]),
        comingSoon(.newWindow, "New Window", .everyday, [.cmd("n")]),
        comingSoon(.newIncognitoWindow, "New Incognito Window", .everyday, [.cmdShift("n")]),
        available(.closeCurrentTab, "Close Current Tab", .everyday, [.cmd("w")]),
        comingSoon(.reopenLastClosedTab, "Re-open Last Closed Tab", .everyday, [.cmdShift("t")]),
        comingSoon(.pinOrUnpinCurrentTab, "Pin or Unpin Current Tab", .everyday, [.cmd("d")]),
        available(.copyCurrentURL, "Copy Current URL", .everyday, [.cmdShift("c")]),
        available(.copyCurrentURLAsMarkdown, "Copy Current URL as Markdown", .everyday, [.cmdOptionShift("c")]),
        available(.focusAddressInput, "Change Current Tab URL", .everyday, [.cmd("l")]),
        available(.toggleSidebar, "Show or Hide Sidebar", .everyday, [.cmd("s")]),
        comingSoon(.clearUnpinnedTabs, "Clear Unpinned Tabs", .everyday, [.cmdShift("k")])
    ]

    private static let quickNavigationActions: [ShortcutAction] = [
        available(.selectTab1, "Go to Tab 1", .quickNavigation, [.cmd("1")]),
        available(.selectTab2, "Go to Tab 2", .quickNavigation, [.cmd("2")]),
        available(.selectTab3, "Go to Tab 3", .quickNavigation, [.cmd("3")]),
        available(.selectTab4, "Go to Tab 4", .quickNavigation, [.cmd("4")]),
        available(.selectTab5, "Go to Tab 5", .quickNavigation, [.cmd("5")]),
        available(.selectTab6, "Go to Tab 6", .quickNavigation, [.cmd("6")]),
        available(.selectTab7, "Go to Tab 7", .quickNavigation, [.cmd("7")]),
        available(.selectTab8, "Go to Tab 8", .quickNavigation, [.cmd("8")]),
        available(.selectTab9, "Go to Tab 9", .quickNavigation, [.cmd("9")]),
        available(.selectRecentTab, "Toggle Recent Tabs", .quickNavigation, [.control(ShortcutBinding.tabKey)]),
        available(.selectPreviousTab, "Previous Tab", .quickNavigation, [.cmdOption(ShortcutBinding.upArrowKey)]),
        available(.selectNextTab, "Next Tab", .quickNavigation, [.cmdOption(ShortcutBinding.downArrowKey)]),
        available(.goBack, "Go Back", .quickNavigation, [.cmd(ShortcutBinding.leftArrowKey), .cmd("[")]),
        available(.goForward, "Go Forward", .quickNavigation, [.cmd(ShortcutBinding.rightArrowKey), .cmd("]")]),
        available(.reloadOrStopLoading, "Reload or Stop Loading", .quickNavigation, [.cmd("r")])
    ]

    private static let otherActions: [ShortcutAction] = [
        comingSoon(.viewHistory, "View History", .other, [.cmd("y")]),
        available(.zoomIn, "Zoom In Webpage", .other, [.cmd("+")]),
        available(.zoomOut, "Zoom Out Webpage", .other, [.cmd("-")]),
        available(.resetZoom, "Reset Webpage Zoom", .other, [.cmd("0")]),
        available(.findInPage, "Find in Webpage", .other, [.cmd("f")])
    ]

    private static func available(_ id: ShortcutActionID, _ title: String, _ category: ShortcutCategory, _ bindings: [ShortcutBinding]) -> ShortcutAction {
        ShortcutAction(id: id, title: title, category: category, defaultBindings: bindings, availability: .available)
    }

    private static func comingSoon(_ id: ShortcutActionID, _ title: String, _ category: ShortcutCategory, _ bindings: [ShortcutBinding]) -> ShortcutAction {
        ShortcutAction(id: id, title: title, category: category, defaultBindings: bindings, availability: .comingSoon)
    }
}

private extension ShortcutBinding {
    static func cmd(_ key: String) -> ShortcutBinding {
        ShortcutBinding(key: key, modifiers: [.command])
    }

    static func cmdShift(_ key: String) -> ShortcutBinding {
        ShortcutBinding(key: key, modifiers: [.command, .shift])
    }

    static func cmdOption(_ key: String) -> ShortcutBinding {
        ShortcutBinding(key: key, modifiers: [.command, .option])
    }

    static func cmdOptionShift(_ key: String) -> ShortcutBinding {
        ShortcutBinding(key: key, modifiers: [.command, .option, .shift])
    }

    static func control(_ key: String) -> ShortcutBinding {
        ShortcutBinding(key: key, modifiers: [.control])
    }
}
