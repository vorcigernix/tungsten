import Foundation

@Observable @MainActor
final class LivePageSessionHost {
    private let maximumCachedPageSessions = 10

    private(set) var activePageSession: BrowserPageSession?
    @ObservationIgnored private var cachedPageSessions: [BrowserTab.ID: BrowserPageSession] = [:]
    @ObservationIgnored private var recentTabIDs: [BrowserTab.ID] = []
    @ObservationIgnored private var closingPageSessions: [BrowserPageSession] = []

    func activate(
        tab: BrowserTab,
        privacyMode: BrowserTabPrivacyMode,
        torConfiguration: TorProxyConfiguration,
        configure: (BrowserPageSession) -> Void
    ) {
        guard let urlString = tab.urlString else {
            BrowserPerformanceLog.event("livePage.activate.blankTab", metadata: [
                "tab": BrowserPerformanceLog.shortID(tab.id)
            ])
            activePageSession = nil
            return
        }
        if activePageSession?.tabID == tab.id {
            touchCachedPageSession(tabID: tab.id)
            BrowserPerformanceLog.event("livePage.activate.alreadyActive", metadata: [
                "tab": BrowserPerformanceLog.shortID(tab.id)
            ])
            return
        }

        if let activePageSession {
            BrowserPerformanceLog.event("livePage.activate.keepPrevious", metadata: [
                "old_tab": BrowserPerformanceLog.shortID(activePageSession.tabID),
                "new_tab": BrowserPerformanceLog.shortID(tab.id)
            ])
        }

        if let session = cachedPageSessions[tab.id] {
            configure(session)
            activePageSession = session
            touchCachedPageSession(tabID: tab.id)
            if session.urlString != urlString {
                session.navigate(to: urlString)
            }
            BrowserPerformanceLog.event("livePage.activate.reusedSession", metadata: [
                "tab": BrowserPerformanceLog.shortID(tab.id),
                "session": BrowserPerformanceLog.shortID(session.id),
                "cached_page_count": cachedPageSessions.count
            ])
            return
        }

        let pageTitle = tab.title ?? ""
        let session = BrowserPageSession(
            tabID: tab.id,
            initialURL: urlString,
            title: pageTitle.isEmpty ? "New Page" : pageTitle,
            privacyMode: privacyMode,
            torConfiguration: torConfiguration
        )
        configure(session)
        cachedPageSessions[tab.id] = session
        activePageSession = session
        touchCachedPageSession(tabID: tab.id)
        evictStalePageSessionsIfNeeded()
        BrowserPerformanceLog.event("livePage.activate.createdSession", metadata: [
            "tab": BrowserPerformanceLog.shortID(tab.id),
            "session": BrowserPerformanceLog.shortID(session.id),
            "is_incognito": privacyMode.isEphemeral,
            "privacy_mode": privacyMode.rawValue,
            "cached_page_count": cachedPageSessions.count
        ])
    }

    func closeActivePage() {
        guard let activePageSession else {
            return
        }

        closePage(tabID: activePageSession.tabID)
    }

    func closePage(tabID: BrowserTab.ID) {
        guard let session = cachedPageSessions.removeValue(forKey: tabID) else {
            if activePageSession?.tabID == tabID {
                activePageSession = nil
            }
            recentTabIDs.removeAll { $0 == tabID }
            return
        }

        BrowserPerformanceLog.event("livePage.closeCached", metadata: [
            "tab": BrowserPerformanceLog.shortID(tabID),
            "session": BrowserPerformanceLog.shortID(session.id),
            "was_active": activePageSession === session,
            "cached_page_count": cachedPageSessions.count
        ])
        recentTabIDs.removeAll { $0 == tabID }
        if activePageSession === session {
            activePageSession = nil
        }
        session.closeBrowser()
    }

    func closePages(tabIDs: [BrowserTab.ID]) {
        for tabID in tabIDs {
            closePage(tabID: tabID)
        }
    }

    func closeActivePageForWindowClose() {
        closeCachedPagesForWindowClose()
    }

    func closeCachedPagesForWindowClose() {
        guard cachedPageSessions.isEmpty == false else {
            activePageSession = nil
            return
        }

        let activeSession = activePageSession
        let sessions = Array(cachedPageSessions.values)
        cachedPageSessions.removeAll()
        recentTabIDs.removeAll()
        activePageSession = nil
        closingPageSessions.append(contentsOf: sessions)

        for session in sessions {
            let originalOnClose = session.onBrowserClose
            session.onBrowserClose = { [weak self, weak session] in
                originalOnClose?()
                guard let self, let session else {
                    return
                }
                self.closingPageSessions.removeAll { $0 === session }
            }

            if session === activeSession {
                session.closeBrowserForWindowClose()
            } else {
                session.closeBrowser()
            }
        }
    }

    private func touchCachedPageSession(tabID: BrowserTab.ID) {
        recentTabIDs.removeAll { $0 == tabID }
        recentTabIDs.append(tabID)
    }

    private func evictStalePageSessionsIfNeeded() {
        while cachedPageSessions.count > maximumCachedPageSessions,
              let evictedTabID = recentTabIDs.first {
            recentTabIDs.removeFirst()
            guard let evictedSession = cachedPageSessions.removeValue(forKey: evictedTabID) else {
                continue
            }

            BrowserPerformanceLog.event("livePage.evictCached", metadata: [
                "tab": BrowserPerformanceLog.shortID(evictedTabID),
                "session": BrowserPerformanceLog.shortID(evictedSession.id),
                "cached_page_count": cachedPageSessions.count
            ])
            evictedSession.closeBrowser()
        }
    }
}
