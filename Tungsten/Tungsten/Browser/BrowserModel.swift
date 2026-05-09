/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Browser thread state and navigation actions.
*/

import AppKit
import Foundation

@Observable @MainActor
final class BrowserModel {
    let kind: BrowserWindowKind
    let appPreferences: AppPreferences
    let historyStore: HistoryStore

    var threads: [BrowserThread] = []
    var selectedThreadID: BrowserThread.ID? {
        didSet {
            guard oldValue != selectedThreadID else {
                return
            }

            if let oldValue {
                previousSelectedThreadID = oldValue
            }

            isFindBarVisible = false
            findText = ""
            activateSelectedThreadPage()
            persistThreads()
        }
    }

    var defaultNewThreadURL: String {
        appPreferences.searchEngine.homepageURL
    }

    var addressText: String = ""
    var addressFocusRequestID = 0
    var isSidebarVisible = true
    var isFindBarVisible = false
    var isHistoryVisible = false
    var isGeneratingResponse = false
    var findText = ""
    var findFocusRequestID = 0

    var selectedThread: BrowserThread? {
        guard let selectedThreadID else {
            return nil
        }

        return threads.first { $0.id == selectedThreadID }
    }

    var activePageSession: BrowserPageSession? {
        livePageHost.activePageSession
    }

    var isSelectedThreadGeneratingResponse: Bool {
        guard isGeneratingResponse, let selectedThreadID else {
            return false
        }

        return pendingResponseThreadID == selectedThreadID
    }

    @ObservationIgnored private var previousSelectedThreadID: BrowserThread.ID?
    @ObservationIgnored private let threadStore: BrowserThreadStore
    @ObservationIgnored private let livePageHost = LivePageSessionHost()
    @ObservationIgnored nonisolated(unsafe) private let aiResponseCoordinator: AIResponseCoordinator
    @ObservationIgnored private var responseTask: Task<Void, Never>?
    @ObservationIgnored private var pendingResponseID: UUID?
    @ObservationIgnored private var pendingResponseThreadID: BrowserThread.ID?
    @ObservationIgnored private var closedThreads: [BrowserThread] = []
    @ObservationIgnored private var didCloseBrowsersForWindowClose = false
    @ObservationIgnored private var windowCloseCompletion: (() -> Void)?

    init(
        kind: BrowserWindowKind = .normal,
        historyStore: HistoryStore = HistoryStore(),
        appPreferences: AppPreferences = AppPreferences(),
        threadStore: BrowserThreadStore? = nil,
        localAI: LocalAIAnswering? = nil
    ) {
        self.kind = kind
        self.historyStore = historyStore
        self.appPreferences = appPreferences

        let resolvedThreadStore: BrowserThreadStore
        if let threadStore {
            resolvedThreadStore = threadStore
        } else if kind.isIncognito {
            resolvedThreadStore = BrowserThreadStore(scope: .memoryOnly)
        } else {
            resolvedThreadStore = BrowserThreadStore(
                scope: .persistent(windowSessionID: BrowserThreadStore.makeWindowSessionID())
            )
        }
        self.threadStore = resolvedThreadStore

        let resolvedLocalAI = localAI ?? ProviderBackedLocalAIResponder(
            provider: { appPreferences.localAIProvider }
        )
        aiResponseCoordinator = AIResponseCoordinator(localAI: resolvedLocalAI)

        let snapshot = resolvedThreadStore.load()
        threads = snapshot.threads

        if threads.isEmpty {
            createThread()
            activateSelectedThreadPage()
            persistThreads()
        } else if let snapshotSelectedThreadID = snapshot.selectedThreadID,
                  threads.contains(where: { $0.id == snapshotSelectedThreadID }) {
            selectedThreadID = snapshotSelectedThreadID
            activateSelectedThreadPage()
        } else {
            selectedThreadID = threads.first?.id
            activateSelectedThreadPage()
            persistThreads()
        }
    }

    func createThread() {
        createThread(navigateTo: defaultNewThreadURL)
    }

    func closeSelectedThread() {
        guard let selectedThread else {
            return
        }

        close(selectedThread)
    }

    func close(_ thread: BrowserThread) {
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else {
            return
        }

        if pendingResponseThreadID == thread.id {
            cancelPendingResponse()
        }

        if kind == .normal {
            closedThreads.append(thread)
        }

        let selectedWasClosed = selectedThreadID == thread.id
        threads.remove(at: index)

        if threads.isEmpty {
            selectedThreadID = nil
            createThread()
            return
        }

        if selectedWasClosed {
            let nextIndex = min(index, threads.count - 1)
            selectedThreadID = threads[nextIndex].id
        } else {
            persistThreads()
        }
    }

    func toggleThreadPin(_ thread: BrowserThread) {
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else {
            return
        }

        threads[index].isPinned.toggle()
        persistThreads()
    }

    func toggleSelectedThreadPin() {
        guard let selectedThread else {
            return
        }

        toggleThreadPin(selectedThread)
    }

    func clearUnpinnedThreads() {
        let selectedWasRemoved = selectedThread.map { $0.isPinned == false } ?? false
        let pinnedThreads = threads.filter(\.isPinned)

        guard pinnedThreads.count != threads.count else {
            return
        }

        if let pendingResponseThreadID,
           pinnedThreads.contains(where: { $0.id == pendingResponseThreadID }) == false {
            cancelPendingResponse()
        }

        if pinnedThreads.isEmpty {
            selectedThreadID = nil
            createThread()
        } else {
            let oldSelectedThreadID = selectedThreadID
            threads = pinnedThreads

            if let oldSelectedThreadID,
               threads.contains(where: { $0.id == oldSelectedThreadID }) {
                selectedThreadID = oldSelectedThreadID
            } else {
                selectedThreadID = threads.first?.id
            }
        }

        if selectedWasRemoved {
            isFindBarVisible = false
            findText = ""
        }

        persistThreads()
    }

    func reopenLastClosedThread() {
        guard kind == .normal, let closedThread = closedThreads.popLast() else {
            return
        }

        threads.append(closedThread)
        selectedThreadID = closedThread.id
    }

    func selectThread(atZeroBasedIndex index: Int) {
        guard threads.indices.contains(index) else {
            return
        }

        selectedThreadID = threads[index].id
    }

    func selectPreviousThread() {
        guard
            let selectedThreadID,
            let index = threads.firstIndex(where: { $0.id == selectedThreadID }),
            index > threads.startIndex
        else {
            return
        }

        self.selectedThreadID = threads[index - 1].id
    }

    func selectNextThread() {
        guard
            let selectedThreadID,
            let index = threads.firstIndex(where: { $0.id == selectedThreadID }),
            index < threads.index(before: threads.endIndex)
        else {
            return
        }

        self.selectedThreadID = threads[index + 1].id
    }

    func selectRecentThread() {
        guard
            let previousSelectedThreadID,
            threads.contains(where: { $0.id == previousSelectedThreadID })
        else {
            return
        }

        selectedThreadID = previousSelectedThreadID
    }

    func activatePageTurnInSelectedThread(_ pageTurnID: BrowserTurn.ID) {
        guard let index = selectedThreadIndex else {
            return
        }

        threads[index].activatePageTurn(pageTurnID)
        activateSelectedThreadPage()
        persistThreads()
    }

    func showHistory() {
        isHistoryVisible = true
    }

    func closeHistory() {
        isHistoryVisible = false
    }

    func openHistoryEntry(_ entry: HistoryEntry) {
        appendPageTurnToSelectedThread(urlString: entry.urlString)
        closeHistory()
    }

    func copyActivePageURL() {
        guard let urlString = activePageSession?.urlString else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }

    func copyActivePageURLAsMarkdown() {
        guard let pageSession = activePageSession else {
            return
        }

        let title = pageSession.displayTitle
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        let markdown = "[\(title)](\(pageSession.urlString))"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func focusAddressInput() {
        addressText = activePageSession?.urlString ?? addressText
        addressFocusRequestID += 1
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
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
        guard let submission = BrowserInputClassifier.submission(
            for: addressText,
            searchEngine: appPreferences.searchEngine
        ) else {
            return
        }

        addressText = ""

        switch submission {
        case .page(let urlString):
            appendPageTurnToSelectedThread(urlString: urlString)
        case .question(let question):
            appendQuestionTurnToSelectedThread(question)
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
        cancelPendingResponse()
        isFindBarVisible = false
        isHistoryVisible = false
        findText = ""
        windowCloseCompletion = completion

        guard let pageSession = activePageSession else {
            finishWindowCloseIfNeeded()
            return
        }

        let originalOnBrowserClose = pageSession.onBrowserClose
        pageSession.onBrowserClose = { [weak self] in
            originalOnBrowserClose?()
            self?.finishWindowCloseIfNeeded()
        }

        livePageHost.closeActivePageForWindowClose()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.finishWindowCloseIfNeeded()
        }
    }

    private var selectedThreadIndex: Int? {
        guard let selectedThreadID else {
            return nil
        }

        return threads.firstIndex { $0.id == selectedThreadID }
    }

    private func createThread(navigateTo urlString: String) {
        var thread = BrowserThread()
        let pageTurnID = thread.appendPage(urlString: urlString)
        thread.activatePageTurn(pageTurnID)
        threads.append(thread)
        selectedThreadID = thread.id
    }

    private func appendPageTurnToSelectedThread(urlString: String) {
        if selectedThreadIndex == nil {
            createThread(navigateTo: urlString)
            return
        }

        guard let index = selectedThreadIndex else {
            return
        }

        let pageTurnID = threads[index].appendPage(urlString: urlString)
        threads[index].activatePageTurn(pageTurnID)
        activateSelectedThreadPage()
        persistThreads()
    }

    private func appendQuestionTurnToSelectedThread(_ question: String) {
        if selectedThreadIndex == nil {
            createThread()
        }

        guard let threadID = selectedThreadID,
              let index = selectedThreadIndex else {
            return
        }

        threads[index].appendQuestion(question)
        persistThreads()

        responseTask?.cancel()
        let responseID = UUID()
        let fallbackSearchEngine = appPreferences.searchEngine
        let pageContext = activePageSession
        pendingResponseID = responseID
        pendingResponseThreadID = threadID
        isGeneratingResponse = true

        responseTask = Task { [weak self, responseID] in
            guard let self else {
                return
            }

            let pageContentContext = await pageContext?.pageContentContext()
            let result = await aiResponseCoordinator.response(
                for: question,
                searchEngine: fallbackSearchEngine,
                pageContext: pageContentContext
            )
            guard Task.isCancelled == false else {
                finishPendingResponseIfCurrent(responseID)
                return
            }

            handleAIResponse(result, for: threadID, responseID: responseID)
        }
    }

    private func handleAIResponse(
        _ result: AIResponseResult,
        for threadID: BrowserThread.ID,
        responseID: UUID
    ) {
        guard pendingResponseID == responseID else {
            return
        }

        guard let index = threads.firstIndex(where: { $0.id == threadID }) else {
            finishPendingResponseIfCurrent(responseID)
            return
        }

        switch result {
        case .assistant(let answer):
            threads[index].appendAssistantResponse(answer)
        case .fallbackPage(let systemMessage, let urlString):
            threads[index].appendSystemMessage(systemMessage)
            let pageTurnID = threads[index].appendPage(urlString: urlString)
            threads[index].activatePageTurn(pageTurnID)

            if selectedThreadID == threadID {
                activateSelectedThreadPage()
            }
        }

        persistThreads()
        finishPendingResponseIfCurrent(responseID)
    }

    private func finishPendingResponseIfCurrent(_ responseID: UUID) {
        guard pendingResponseID == responseID else {
            return
        }

        pendingResponseID = nil
        pendingResponseThreadID = nil
        responseTask = nil
        isGeneratingResponse = false
    }

    private func cancelPendingResponse() {
        responseTask?.cancel()
        responseTask = nil
        pendingResponseID = nil
        pendingResponseThreadID = nil
        isGeneratingResponse = false
    }

    private func activateSelectedThreadPage() {
        guard let pageTurn = selectedThread?.activePageTurn else {
            livePageHost.closeActivePage()
            return
        }

        livePageHost.activate(
            pageTurn: pageTurn,
            isIncognito: kind.isIncognito
        ) { [weak self] pageSession in
            self?.configurePageCallbacks(for: pageSession)
        }
    }

    private func configurePageCallbacks(for pageSession: BrowserPageSession) {
        pageSession.onURLChange = { [weak self, weak pageSession] urlString in
            guard let self, let pageSession else {
                return
            }

            self.updatePageTurnMetadata(
                pageTurnID: pageSession.pageTurnID,
                urlString: urlString
            )
            self.recordHistoryVisit(urlString, pageSession: pageSession)
        }

        pageSession.onTitleChange = { [weak self, weak pageSession] title in
            guard let self, let pageSession else {
                return
            }

            self.updatePageTurnMetadata(
                pageTurnID: pageSession.pageTurnID,
                title: title
            )
            self.recordHistoryTitle(title, pageSession: pageSession)
        }

        pageSession.onFaviconURLChange = { [weak self, weak pageSession] faviconURLString in
            guard let self, let pageSession else {
                return
            }

            self.updatePageTurnMetadata(
                pageTurnID: pageSession.pageTurnID,
                faviconURLString: faviconURLString
            )
        }
    }

    private func updatePageTurnMetadata(
        pageTurnID: BrowserTurn.ID,
        urlString: String? = nil,
        title: String? = nil,
        faviconURLString: String? = nil
    ) {
        guard let index = threads.firstIndex(where: { thread in
            thread.turns.contains { $0.id == pageTurnID && $0.kind == .page }
        }) else {
            return
        }

        threads[index].updatePageMetadata(
            turnID: pageTurnID,
            urlString: urlString,
            title: title,
            faviconURLString: faviconURLString
        )
        persistThreads()
    }

    private func recordHistoryVisit(_ urlString: String, pageSession: BrowserPageSession) {
        guard
            kind == .normal,
            activePageSession === pageSession
        else {
            return
        }

        historyStore.recordVisit(urlString: urlString, title: pageSession.displayTitle)
    }

    private func recordHistoryTitle(_ title: String, pageSession: BrowserPageSession) {
        guard
            kind == .normal,
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

    private func persistThreads() {
        threadStore.save(threads: threads, selectedThreadID: selectedThreadID)
    }
}
