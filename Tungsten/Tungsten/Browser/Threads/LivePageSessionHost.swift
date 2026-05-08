import Foundation

@Observable @MainActor
final class LivePageSessionHost {
    private(set) var activePageSession: BrowserPageSession?
    @ObservationIgnored private var closingPageSession: BrowserPageSession?

    func activate(pageTurn: BrowserTurn, isIncognito: Bool, configure: (BrowserPageSession) -> Void) {
        guard pageTurn.kind == .page, let urlString = pageTurn.urlString else {
            closeActivePage()
            return
        }
        if activePageSession?.pageTurnID == pageTurn.id { return }
        closeActivePage()

        let pageTitle = pageTurn.title ?? ""
        let session = BrowserPageSession(
            pageTurnID: pageTurn.id,
            initialURL: urlString,
            title: pageTitle.isEmpty ? "New Page" : pageTitle,
            isIncognito: isIncognito
        )
        configure(session)
        activePageSession = session
    }

    func closeActivePage() {
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
