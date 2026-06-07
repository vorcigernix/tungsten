import Foundation

@Observable @MainActor
final class LivePageSessionHost {
    private(set) var activePageSession: BrowserPageSession?
    @ObservationIgnored private var closingPageSession: BrowserPageSession?

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
            closeActivePage()
            return
        }
        if activePageSession?.tabID == tab.id {
            BrowserPerformanceLog.event("livePage.activate.alreadyActive", metadata: [
                "tab": BrowserPerformanceLog.shortID(tab.id)
            ])
            return
        }
        if let activePageSession {
            BrowserPerformanceLog.event("livePage.activate.closePrevious", metadata: [
                "old_tab": BrowserPerformanceLog.shortID(activePageSession.tabID),
                "new_tab": BrowserPerformanceLog.shortID(tab.id)
            ])
        }
        closeActivePage()

        let pageTitle = tab.title ?? ""
        let session = BrowserPageSession(
            tabID: tab.id,
            initialURL: urlString,
            title: pageTitle.isEmpty ? "New Page" : pageTitle,
            privacyMode: privacyMode,
            torConfiguration: torConfiguration
        )
        configure(session)
        activePageSession = session
        BrowserPerformanceLog.event("livePage.activate.createdSession", metadata: [
            "tab": BrowserPerformanceLog.shortID(tab.id),
            "session": BrowserPerformanceLog.shortID(session.id),
            "is_incognito": privacyMode.isEphemeral,
            "privacy_mode": privacyMode.rawValue
        ])
    }

    func closeActivePage() {
        if let activePageSession {
            BrowserPerformanceLog.event("livePage.closeActive", metadata: [
                "tab": BrowserPerformanceLog.shortID(activePageSession.tabID),
                "session": BrowserPerformanceLog.shortID(activePageSession.id)
            ])
        }
        activePageSession?.closeBrowser()
        activePageSession = nil
    }

    func closeActivePageForWindowClose() {
        guard let session = activePageSession else {
            return
        }

        activePageSession = nil
        closingPageSession = session

        let originalOnClose = session.onBrowserClose
        session.onBrowserClose = { [weak self, weak session] in
            originalOnClose?()
            guard let self, self.closingPageSession === session else {
                return
            }
            self.closingPageSession = nil
        }

        session.closeBrowserForWindowClose()
    }
}
