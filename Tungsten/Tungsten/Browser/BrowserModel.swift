/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Browser tab state and navigation actions.
*/

import AppKit
import Foundation

typealias BrowserTab = BrowserPageSession

@Observable @MainActor
final class BrowserModel {
    let kind: BrowserWindowKind
    let appPreferences: AppPreferences
    var tabs: [BrowserTab] = []

    var defaultNewTabURL: String {
        appPreferences.searchEngine.homepageURL
    }
    var selectedTabID: BrowserTab.ID? {
        didSet {
            guard oldValue != selectedTabID else {
                return
            }
            if let oldValue {
                previousSelectedTabID = oldValue
            }
        }
    }
    var addressText: String = ""
    var addressFocusRequestID = 0
    var isSidebarVisible = true
    var isFindBarVisible = false
    var isHistoryVisible = false
    var findText = ""
    var findFocusRequestID = 0

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var activePageSession: BrowserPageSession? { selectedTab }

    private var previousSelectedTabID: BrowserTab.ID?
    let historyStore: HistoryStore
    private var closedTabs: [ClosedTab] = []
    private var didCloseBrowsersForWindowClose = false
    private var pendingWindowCloseTabIDs: Set<BrowserTab.ID> = []
    private var windowCloseCompletion: (() -> Void)?

    init(
        kind: BrowserWindowKind = .normal,
        historyStore: HistoryStore = HistoryStore(),
        appPreferences: AppPreferences = AppPreferences()
    ) {
        self.kind = kind
        self.historyStore = historyStore
        self.appPreferences = appPreferences
        addTab()
    }

    func addTab(navigateTo urlString: String? = nil) {
        let target = urlString ?? defaultNewTabURL
        let tab = makeTab(navigateTo: target)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else {
            return
        }

        if tabs.count == 1 {
            tab.resetForLastTabClose(to: defaultNewTabURL)
            selectedTabID = tab.id
            isFindBarVisible = false
            findText = ""
            return
        }

        if kind == .normal {
            closedTabs.append(
                ClosedTab(
                    urlString: tab.urlString,
                    title: tab.displayTitle,
                    isPinned: tab.isPinned
                )
            )
        }

        tab.closeBrowser()
        tabs.remove(at: index)

        if tabs.isEmpty {
            addTab()
            return
        }

        if selectedTabID == tab.id {
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
        }
    }

    func closeSelectedTab() {
        guard let selectedTab else {
            return
        }
        close(selectedTab)
    }

    func closeBrowsersForWindowClose(completion: @escaping () -> Void) {
        guard didCloseBrowsersForWindowClose == false else {
            if windowCloseCompletion == nil {
                completion()
            }
            return
        }

        didCloseBrowsersForWindowClose = true
        isFindBarVisible = false
        isHistoryVisible = false
        findText = ""

        let closingTabs = tabs
        pendingWindowCloseTabIDs = Set(closingTabs.map(\.id))
        windowCloseCompletion = completion

        guard closingTabs.isEmpty == false else {
            finishWindowCloseIfNeeded()
            return
        }

        for tab in closingTabs {
            let tabID = tab.id
            tab.onBrowserClose = { [weak self] in
                self?.markWindowCloseBrowserClosed(tabID)
            }
        }

        for tab in closingTabs {
            tab.closeBrowserForWindowClose()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.finishWindowCloseIfNeeded()
        }
    }

    func toggleSelectedTabPin() {
        guard let selectedTab else {
            return
        }

        togglePin(selectedTab)
    }

    func togglePin(_ tab: BrowserTab) {
        guard tabs.contains(where: { $0.id == tab.id }) else {
            return
        }

        tab.isPinned.toggle()
    }

    func clearUnpinnedTabs() {
        let pinnedTabs = tabs.filter(\.isPinned)
        let removedTabs = tabs.filter { $0.isPinned == false }
        let selectedWasRemoved = selectedTab.map { $0.isPinned == false } ?? false

        guard removedTabs.isEmpty == false else {
            return
        }

        for tab in removedTabs {
            tab.closeBrowser()
        }

        if pinnedTabs.isEmpty {
            tabs.removeAll()
            isFindBarVisible = false
            findText = ""
            addTab()
            return
        }

        let oldSelectedTabID = selectedTabID
        tabs = pinnedTabs

        if let oldSelectedTabID, tabs.contains(where: { $0.id == oldSelectedTabID }) {
            selectedTabID = oldSelectedTabID
        } else {
            selectedTabID = tabs.first?.id
        }

        if selectedWasRemoved {
            isFindBarVisible = false
            findText = ""
        }
    }

    func reopenLastClosedTab() {
        guard kind == .normal, let closedTab = closedTabs.popLast() else {
            return
        }

        let tab = makeTab(navigateTo: closedTab.urlString)
        tab.title = closedTab.title
        tab.isPinned = closedTab.isPinned
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func showHistory() {
        isHistoryVisible = true
    }

    func closeHistory() {
        isHistoryVisible = false
    }

    func openHistoryEntry(_ entry: HistoryEntry) {
        if let selectedTab {
            selectedTab.navigate(to: entry.urlString)
        } else {
            addTab(navigateTo: entry.urlString)
        }

        closeHistory()
    }

    func copySelectedTabURL() {
        guard let urlString = selectedTab?.urlString else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }

    func copySelectedTabURLAsMarkdown() {
        guard let selectedTab else {
            return
        }

        let title = selectedTab.displayTitle
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        let markdown = "[\(title)](\(selectedTab.urlString))"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func focusAddressInput() {
        addressText = selectedTab?.urlString ?? addressText
        addressFocusRequestID += 1
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    func zoomIn() {
        selectedTab?.zoomIn()
    }

    func zoomOut() {
        selectedTab?.zoomOut()
    }

    func resetZoom() {
        selectedTab?.resetZoom()
    }

    func showFindInPage() {
        isFindBarVisible = true
        findFocusRequestID += 1

        if findText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            runFindInPage(findNext: false, forward: true)
        }
    }

    func closeFindInPage() {
        selectedTab?.stopFinding(clearSelection: true)
        isFindBarVisible = false
    }

    func updateFindText(_ text: String) {
        findText = text

        guard findText.isEmpty == false else {
            selectedTab?.stopFinding(clearSelection: true)
            return
        }

        runFindInPage(findNext: false, forward: true)
    }

    func findNextInPage() {
        runFindInPage(findNext: true, forward: true)
    }

    func findPreviousInPage() {
        runFindInPage(findNext: true, forward: false)
    }

    func selectTab(atZeroBasedIndex index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }
        selectedTabID = tabs[index].id
    }

    func selectPreviousTab() {
        guard
            let selectedTabID,
            let index = tabs.firstIndex(where: { $0.id == selectedTabID }),
            index > tabs.startIndex
        else {
            return
        }

        self.selectedTabID = tabs[index - 1].id
    }

    func selectNextTab() {
        guard
            let selectedTabID,
            let index = tabs.firstIndex(where: { $0.id == selectedTabID }),
            index < tabs.index(before: tabs.endIndex)
        else {
            return
        }

        self.selectedTabID = tabs[index + 1].id
    }

    func selectRecentTab() {
        guard
            let previousSelectedTabID,
            tabs.contains(where: { $0.id == previousSelectedTabID })
        else {
            return
        }

        selectedTabID = previousSelectedTabID
    }

    func submitAddressBar() {
        guard
            let target = AddressResolver.navigationTarget(for: addressText, searchEngine: appPreferences.searchEngine),
            let selectedTab
        else {
            return
        }

        selectedTab.navigate(to: target)
        addressText = ""
    }

    private func runFindInPage(findNext: Bool, forward: Bool) {
        guard findText.isEmpty == false else {
            return
        }

        selectedTab?.findInPage(findText, forward: forward, matchCase: false, findNext: findNext)
    }

    private func markWindowCloseBrowserClosed(_ tabID: BrowserTab.ID) {
        pendingWindowCloseTabIDs.remove(tabID)
        tabs.first { $0.id == tabID }?.onBrowserClose = nil

        if pendingWindowCloseTabIDs.isEmpty {
            finishWindowCloseIfNeeded()
        }
    }

    private func finishWindowCloseIfNeeded() {
        guard let completion = windowCloseCompletion else {
            return
        }

        pendingWindowCloseTabIDs.removeAll()
        windowCloseCompletion = nil
        completion()
    }

    private func makeTab(navigateTo urlString: String) -> BrowserTab {
        let tab = BrowserTab(initialURL: urlString, isIncognito: kind.isIncognito)
        configureHistoryCallbacks(for: tab)
        return tab
    }

    private func configureHistoryCallbacks(for tab: BrowserTab) {
        tab.onURLChange = { [weak self, weak tab] urlString in
            guard let self, let tab else {
                return
            }

            self.recordHistoryVisit(urlString, tab: tab)
        }

        tab.onTitleChange = { [weak self, weak tab] title in
            guard let self, let tab else {
                return
            }

            self.recordHistoryTitle(title, tab: tab)
        }
    }

    private func recordHistoryVisit(_ urlString: String, tab: BrowserTab) {
        guard
            kind == .normal,
            tabs.contains(where: { $0.id == tab.id })
        else {
            return
        }

        historyStore.recordVisit(urlString: urlString, title: tab.displayTitle)
    }

    private func recordHistoryTitle(_ title: String, tab: BrowserTab) {
        guard
            kind == .normal,
            tabs.contains(where: { $0.id == tab.id })
        else {
            return
        }

        historyStore.updateTitle(for: tab.urlString, title: title)
    }
}
