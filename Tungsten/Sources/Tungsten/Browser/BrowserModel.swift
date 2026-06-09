/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Browser tab state and navigation actions.
*/

import AppKit
import Foundation

@Observable @MainActor
final class BrowserModel {
    let kind: BrowserWindowKind
    let appPreferences: AppPreferences
    let historyStore: HistoryStore

    var tabs: [BrowserTab] = []
    var selectedTabID: BrowserTab.ID? {
        didSet {
            guard oldValue != selectedTabID else {
                return
            }

            if let oldValue {
                previousSelectedTabID = oldValue
            }

            BrowserPerformanceLog.event("tab.selection.changed", metadata: [
                "old_tab": BrowserPerformanceLog.shortID(oldValue),
                "new_tab": BrowserPerformanceLog.shortID(selectedTabID),
                "has_url": selectedTab?.urlString != nil
            ])

            isFindBarVisible = false
            findText = ""
            addressText = selectedTab?.urlString ?? ""
            activateSelectedTabPage()
            persistTabs()
        }
    }

    var addressText: String = ""
    var addressFocusRequestID = 0
    var isFindBarVisible = false
    var isHistoryVisible = false
    var findText = ""
    var findFocusRequestID = 0

    var selectedTab: BrowserTab? {
        guard let selectedTabID else {
            return nil
        }

        return tabs.first { $0.id == selectedTabID }
    }

    var activePageSession: BrowserPageSession? {
        livePageHost.activePageSession
    }

    @ObservationIgnored private var previousSelectedTabID: BrowserTab.ID?
    @ObservationIgnored private let tabStore: BrowserTabStore
    @ObservationIgnored private let livePageHost = LivePageSessionHost()
    @ObservationIgnored private var closedTabs: [BrowserTab] = []
    @ObservationIgnored private var didCloseBrowsersForWindowClose = false
    @ObservationIgnored private var windowCloseCompletion: (() -> Void)?

    init(
        kind: BrowserWindowKind = .normal,
        historyStore: HistoryStore = HistoryStore(),
        appPreferences: AppPreferences = AppPreferences(),
        tabStore: BrowserTabStore? = nil
    ) {
        self.kind = kind
        self.historyStore = historyStore
        self.appPreferences = appPreferences

        let resolvedTabStore: BrowserTabStore
        if let tabStore {
            resolvedTabStore = tabStore
        } else if kind.isIncognito {
            resolvedTabStore = BrowserTabStore(scope: .memoryOnly)
        } else {
            resolvedTabStore = BrowserTabStore(
                scope: .persistent(windowSessionID: BrowserTabStore.makeWindowSessionID())
            )
        }
        self.tabStore = resolvedTabStore

        let snapshot = resolvedTabStore.load()
        tabs = snapshot.tabs

        if tabs.isEmpty {
            createTab()
            persistTabs()
        } else if let snapshotSelectedTabID = snapshot.selectedTabID,
                  tabs.contains(where: { $0.id == snapshotSelectedTabID }) {
            selectedTabID = snapshotSelectedTabID
            addressText = selectedTab?.urlString ?? ""
            activateSelectedTabPage()
        } else {
            selectedTabID = tabs.first?.id
            addressText = selectedTab?.urlString ?? ""
            activateSelectedTabPage()
            persistTabs()
        }
    }

    func createTab(
        urlString: String? = nil,
        title: String? = nil,
        privacyMode: BrowserTabPrivacyMode? = nil
    ) {
        let resolvedPrivacyMode = privacyMode ?? defaultPrivacyMode
        let tab = BrowserTab(urlString: urlString, title: title, privacyMode: resolvedPrivacyMode)
        var metadata: [String: Any] = [
            "tab": BrowserPerformanceLog.shortID(tab.id),
            "has_title": title?.isEmpty == false,
            "privacy_mode": resolvedPrivacyMode.rawValue
        ]
        metadata.merge(BrowserPerformanceLog.urlMetadata(urlString)) { _, new in new }
        BrowserPerformanceLog.event("tab.create", metadata: metadata)

        tabs.append(tab)
        selectedTabID = tab.id
        addressText = urlString ?? ""

        if urlString == nil {
            addressFocusRequestID += 1
        }
    }

    func createIncognitoTab(urlString: String? = nil, title: String? = nil) {
        createTab(urlString: urlString, title: title, privacyMode: .incognito)
    }

    func createTorTab(urlString: String? = nil, title: String? = nil) {
        createTab(urlString: urlString, title: title, privacyMode: .tor)
    }

    func closeSelectedTab() {
        guard let selectedTab else {
            return
        }

        close(selectedTab)
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else {
            return
        }

        if shouldRememberClosedTab(tab) {
            closedTabs.append(tab)
        }

        let selectedWasClosed = selectedTabID == tab.id
        livePageHost.closePage(tabID: tab.id)

        tabs.remove(at: index)

        if tabs.isEmpty {
            selectedTabID = nil
            createTab()
            return
        }

        if selectedWasClosed {
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
        } else {
            persistTabs()
        }
    }

    func closeOtherTabs(keeping tab: BrowserTab) {
        let removedTabs = tabs.filter { $0.id != tab.id }
        guard removedTabs.isEmpty == false else {
            return
        }

        if kind == .normal {
            closedTabs.append(contentsOf: removedTabs.filter { shouldRememberClosedTab($0) })
        }

        livePageHost.closePages(tabIDs: removedTabs.map(\.id))
        tabs = [tab]
        selectedTabID = tab.id
        persistTabs()
    }

    func toggleTabPin(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else {
            return
        }

        tabs[index].isPinned.toggle()
        persistTabs()
    }

    func toggleSelectedTabPin() {
        guard let selectedTab else {
            return
        }

        toggleTabPin(selectedTab)
    }

    func clearUnpinnedTabs() {
        let selectedWasRemoved = selectedTab.map { $0.isPinned == false } ?? false
        let removedTabs = tabs.filter { $0.isPinned == false }
        let pinnedTabs = tabs.filter(\.isPinned)

        guard pinnedTabs.count != tabs.count else {
            return
        }

        if kind == .normal {
            closedTabs.append(contentsOf: removedTabs.filter { shouldRememberClosedTab($0) })
        }

        livePageHost.closePages(tabIDs: removedTabs.map(\.id))
        if pinnedTabs.isEmpty {
            selectedTabID = nil
            createTab()
        } else {
            let oldSelectedTabID = selectedTabID
            tabs = pinnedTabs

            if let oldSelectedTabID,
               tabs.contains(where: { $0.id == oldSelectedTabID }) {
                selectedTabID = oldSelectedTabID
            } else {
                selectedTabID = tabs.first?.id
            }
        }

        if selectedWasRemoved {
            isFindBarVisible = false
            findText = ""
        }

        persistTabs()
    }

    func reopenLastClosedTab() {
        guard kind == .normal, let closedTab = closedTabs.popLast() else {
            return
        }

        var reopenedTab = closedTab
        reopenedTab.updatedAt = Date()
        tabs.append(reopenedTab)
        selectedTabID = reopenedTab.id
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

    func showHistory() {
        isHistoryVisible = true
    }

    func closeHistory() {
        isHistoryVisible = false
    }

    func openHistoryEntry(_ entry: HistoryEntry) {
        navigateSelectedTab(to: entry.urlString)
        closeHistory()
    }

    /// Navigates the selected tab to a URL chosen from chrome surfaces such as
    /// the start page's Favorites and Frequently Visited tiles.
    func openURLString(_ urlString: String) {
        navigateSelectedTab(to: urlString)
    }

    func openContextMenuSearch(for selectedText: String) {
        let query = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return
        }

        let searchURL = appPreferences.searchEngine.searchURL(for: query)
        BrowserPerformanceLog.event("contextMenu.search", metadata: [
            "query_length": query.count,
            "search_engine": appPreferences.searchEngine.rawValue
        ])
        createTab(urlString: searchURL, privacyMode: selectedTabPrivacyMode)
    }

    func openPopupTab(urlString: String, privacyMode: BrowserTabPrivacyMode) {
        let targetURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard targetURLString.isEmpty == false else {
            return
        }

        var metadata: [String: Any] = [
            "privacy_mode": privacyMode.rawValue
        ]
        metadata.merge(BrowserPerformanceLog.urlMetadata(targetURLString)) { _, new in new }
        BrowserPerformanceLog.event("popup.openTab", metadata: metadata)
        createTab(urlString: targetURLString, privacyMode: privacyMode)
    }

    func copyActivePageURL() {
        guard let urlString = activePageSession?.urlString ?? selectedTab?.urlString else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }

    func copyActivePageURLAsMarkdown() {
        guard let selectedTab, let urlString = selectedTab.urlString else {
            return
        }

        let title = selectedTab.displayTitle
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        let markdown = "[\(title)](\(urlString))"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func focusAddressInput() {
        addressText = selectedTab?.urlString ?? ""
        addressFocusRequestID += 1
    }

    func zoomIn() {
        activePageSession?.zoomIn()
    }

    func zoomOut() {
        activePageSession?.zoomOut()
    }

    func resetZoom() {
        activePageSession?.resetZoom()
    }

    func showFindInPage() {
        isFindBarVisible = true
        findFocusRequestID += 1

        if findText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            runFindInPage(findNext: false, forward: true)
        }
    }

    func closeFindInPage() {
        activePageSession?.stopFinding(clearSelection: true)
        isFindBarVisible = false
    }

    func updateFindText(_ text: String) {
        findText = text

        guard findText.isEmpty == false else {
            activePageSession?.stopFinding(clearSelection: true)
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

    func submitAddressBar() {
        let input = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        BrowserPerformanceLog.event("address.submit", metadata: [
            "input_length": input.count,
            "selected_tab": BrowserPerformanceLog.shortID(selectedTabID)
        ])

        guard let submission = BrowserInputClassifier.submission(
            for: addressText,
            searchEngine: appPreferences.searchEngine
        ) else {
            BrowserPerformanceLog.event("address.submit.ignored", metadata: [
                "selected_tab": BrowserPerformanceLog.shortID(selectedTabID)
            ])
            return
        }

        switch submission {
        case .page(let urlString):
            var metadata: [String: Any] = [
                "kind": "page",
                "selected_tab": BrowserPerformanceLog.shortID(selectedTabID)
            ]
            metadata.merge(BrowserPerformanceLog.urlMetadata(urlString)) { _, new in new }
            BrowserPerformanceLog.event("address.submit.classified", metadata: metadata)
            navigateSelectedTab(to: urlString)
        case .question(let question):
            let answerURL = appPreferences.addressBarAIProvider.responseURL(for: question)
            var metadata: [String: Any] = [
                "kind": "question",
                "answer_provider": appPreferences.addressBarAIProvider.rawValue,
                "query_length": question.count,
                "selected_tab": BrowserPerformanceLog.shortID(selectedTabID)
            ]
            metadata.merge(BrowserPerformanceLog.urlMetadata(answerURL)) { _, new in new }
            BrowserPerformanceLog.event("address.submit.classified", metadata: metadata)
            navigateSelectedTab(to: answerURL)
        }
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
        windowCloseCompletion = completion

        if let pageSession = activePageSession {
            let originalOnBrowserClose = pageSession.onBrowserClose
            pageSession.onBrowserClose = { [weak self] in
                originalOnBrowserClose?()
                self?.finishWindowCloseIfNeeded()
            }
        } else {
            finishWindowCloseIfNeeded()
        }

        livePageHost.closeCachedPagesForWindowClose()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.finishWindowCloseIfNeeded()
        }
    }

    private var selectedTabIndex: Int? {
        guard let selectedTabID else {
            return nil
        }

        return tabs.firstIndex { $0.id == selectedTabID }
    }

    private var defaultPrivacyMode: BrowserTabPrivacyMode {
        kind.isIncognito ? .incognito : .normal
    }

    private var selectedTabPrivacyMode: BrowserTabPrivacyMode {
        selectedTab.map(effectivePrivacyMode(for:)) ?? defaultPrivacyMode
    }

    private func navigateSelectedTab(to urlString: String) {
        var metadata: [String: Any] = [
            "selected_tab": BrowserPerformanceLog.shortID(selectedTabID),
            "has_active_session": activePageSession != nil
        ]
        metadata.merge(BrowserPerformanceLog.urlMetadata(urlString)) { _, new in new }
        BrowserPerformanceLog.event("tab.navigateSelected.start", metadata: metadata)

        if selectedTabIndex == nil {
            BrowserPerformanceLog.event("tab.navigateSelected.createsTab", metadata: metadata)
            createTab(urlString: urlString)
            return
        }

        guard let index = selectedTabIndex else {
            BrowserPerformanceLog.event("tab.navigateSelected.noSelection", metadata: metadata)
            return
        }

        tabs[index].update(urlString: urlString, title: nil, faviconURLString: nil)
        addressText = urlString
        persistTabs()

        if activePageSession?.tabID == tabs[index].id {
            BrowserPerformanceLog.event("tab.navigateSelected.activeSession", metadata: [
                "tab": BrowserPerformanceLog.shortID(tabs[index].id)
            ])
            activePageSession?.navigate(to: urlString)
        } else {
            BrowserPerformanceLog.event("tab.navigateSelected.activateSession", metadata: [
                "tab": BrowserPerformanceLog.shortID(tabs[index].id)
            ])
            activateSelectedTabPage()
        }
    }

    private func activateSelectedTabPage() {
        guard let selectedTab else {
            BrowserPerformanceLog.event("tab.activateSelected.empty")
            livePageHost.closeActivePage()
            return
        }

        var metadata: [String: Any] = [
            "tab": BrowserPerformanceLog.shortID(selectedTab.id),
            "is_incognito": effectivePrivacyMode(for: selectedTab).isEphemeral,
            "privacy_mode": effectivePrivacyMode(for: selectedTab).rawValue
        ]
        metadata.merge(BrowserPerformanceLog.urlMetadata(selectedTab.urlString)) { _, new in new }
        BrowserPerformanceLog.event("tab.activateSelected.start", metadata: metadata)

        livePageHost.activate(
            tab: selectedTab,
            privacyMode: effectivePrivacyMode(for: selectedTab),
            torConfiguration: appPreferences.torConfiguration
        ) { [weak self] pageSession in
            self?.configurePageCallbacks(for: pageSession)
        }
    }

    private func configurePageCallbacks(for pageSession: BrowserPageSession) {
        pageSession.configurePopupOpening { [weak self, weak pageSession] urlString in
            guard let self, let pageSession, self.activePageSession === pageSession else {
                return
            }

            self.openPopupTab(urlString: urlString, privacyMode: pageSession.privacyMode)
        }

        pageSession.configureContextMenuSearch(searchEngine: appPreferences.searchEngine) { [weak self] selectedText in
            self?.openContextMenuSearch(for: selectedText)
        }

        pageSession.onURLChange = { [weak self, weak pageSession] urlString in
            guard let self, let pageSession else {
                return
            }

            self.updateTabMetadata(
                tabID: pageSession.tabID,
                urlString: urlString
            )
            self.recordHistoryVisit(urlString, pageSession: pageSession)
        }

        pageSession.onTitleChange = { [weak self, weak pageSession] title in
            guard let self, let pageSession else {
                return
            }

            self.updateTabMetadata(
                tabID: pageSession.tabID,
                title: title
            )
            self.recordHistoryTitle(title, pageSession: pageSession)
        }

        pageSession.onFaviconURLChange = { [weak self, weak pageSession] faviconURLString in
            guard let self, let pageSession else {
                return
            }

            self.updateTabMetadata(
                tabID: pageSession.tabID,
                faviconURLString: faviconURLString
            )
        }
    }

    private func updateTabMetadata(
        tabID: BrowserTab.ID,
        urlString: String? = nil,
        title: String? = nil,
        faviconURLString: String? = nil
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        tabs[index].update(
            urlString: urlString,
            title: title,
            faviconURLString: faviconURLString
        )

        if selectedTabID == tabID, let urlString {
            addressText = urlString
        }
        persistTabs()
    }

    private func recordHistoryVisit(_ urlString: String, pageSession: BrowserPageSession) {
        guard
            kind == .normal,
            selectedTabPrivacyMode == .normal,
            activePageSession === pageSession
        else {
            return
        }

        historyStore.recordVisit(urlString: urlString, title: pageSession.displayTitle)
    }

    private func recordHistoryTitle(_ title: String, pageSession: BrowserPageSession) {
        guard
            kind == .normal,
            selectedTabPrivacyMode == .normal,
            activePageSession === pageSession
        else {
            return
        }

        historyStore.updateTitle(for: pageSession.urlString, title: title)
    }

    private func runFindInPage(findNext: Bool, forward: Bool) {
        guard findText.isEmpty == false else {
            return
        }

        activePageSession?.findInPage(findText, forward: forward, matchCase: false, findNext: findNext)
    }

    private func finishWindowCloseIfNeeded() {
        guard let completion = windowCloseCompletion else {
            return
        }

        windowCloseCompletion = nil
        completion()
    }

    private func shouldRememberClosedTab(_ tab: BrowserTab) -> Bool {
        kind == .normal && effectivePrivacyMode(for: tab) == .normal
    }

    private func effectivePrivacyMode(for tab: BrowserTab) -> BrowserTabPrivacyMode {
        if kind.isIncognito, tab.privacyMode == .normal {
            return .incognito
        }
        return tab.privacyMode
    }

    private func persistTabs() {
        let start = BrowserPerformanceLog.now()
        tabStore.save(tabs: tabs, selectedTabID: selectedTabID)
        BrowserPerformanceLog.duration("tabs.persist", from: start, metadata: [
            "tab_count": tabs.count,
            "selected_tab": BrowserPerformanceLog.shortID(selectedTabID)
        ])
    }
}
