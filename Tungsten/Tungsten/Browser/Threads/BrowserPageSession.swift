import AppKit
import Foundation

@Observable @MainActor
final class BrowserPageSession: Identifiable {
    typealias ID = UUID

    let id = UUID()
    let pageTurnID: BrowserTurn.ID
    let isIncognito: Bool
    var isPinned = false
    var title: String
    var urlString: String
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var favicon: NSImage?

    @ObservationIgnored var onURLChange: ((String) -> Void)?
    @ObservationIgnored var onTitleChange: ((String) -> Void)?
    @ObservationIgnored var onFaviconURLChange: ((String) -> Void)?
    @ObservationIgnored var onBrowserClose: (() -> Void)?

    @ObservationIgnored private var loadedFaviconURL: String?
    @ObservationIgnored private var faviconFetchTask: Task<Void, Never>?

    @ObservationIgnored private let initialURL: String
    @ObservationIgnored private lazy var observer = BrowserPageSessionObserver(pageSession: self)
    @ObservationIgnored lazy var browserController: TungstenBrowserController = {
        let controller = TungstenBrowserController(initialURL: initialURL, incognito: isIncognito)
        controller.delegate = observer
        controller.browserDidCloseHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.onBrowserClose?()
            }
        }
        return controller
    }()

    var displayTitle: String {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return title
        }

        if let host = URLComponents(string: urlString)?.host {
            return host
        }

        return "New Page"
    }

    init(pageTurnID: BrowserTurn.ID, initialURL: String, title: String = "New Page", isIncognito: Bool) {
        self.pageTurnID = pageTurnID
        self.initialURL = initialURL
        self.isIncognito = isIncognito
        self.urlString = initialURL
        self.title = title
    }

    convenience init(initialURL: String, isIncognito: Bool) {
        self.init(pageTurnID: BrowserTurn.ID(), initialURL: initialURL, title: "New Page", isIncognito: isIncognito)
    }

    func navigate(to urlString: String) {
        if URLComponents(string: urlString)?.host != URLComponents(string: self.urlString)?.host {
            favicon = nil
            loadedFaviconURL = nil
        }
        self.urlString = urlString
        onURLChange?(urlString)
        browserController.navigate(toURLString: urlString)
    }

    func updateTitle(_ title: String) {
        self.title = title
        onTitleChange?(title)
    }

    func updateURL(_ urlString: String) {
        self.urlString = urlString
        onURLChange?(urlString)
    }

    func updateFavicon(from urls: [String]) {
        guard let candidate = urls.first(where: { URL(string: $0) != nil }) else {
            return
        }
        if candidate == loadedFaviconURL {
            return
        }
        loadedFaviconURL = candidate
        onFaviconURLChange?(candidate)

        faviconFetchTask?.cancel()
        faviconFetchTask = Task { [weak self, candidate] in
            let image = await FaviconLoader.shared.image(for: candidate)
            await MainActor.run {
                guard let self else { return }
                if self.loadedFaviconURL == candidate {
                    self.favicon = image
                }
            }
        }
    }

    func goBack() {
        browserController.goBack()
    }

    func goForward() {
        browserController.goForward()
    }

    func reload() {
        browserController.reload()
    }

    func stopLoading() {
        browserController.stopLoading()
    }

    func zoomIn() {
        browserController.zoomIn()
    }

    func zoomOut() {
        browserController.zoomOut()
    }

    func resetZoom() {
        browserController.resetZoom()
    }

    func findInPage(_ text: String, forward: Bool, matchCase: Bool, findNext: Bool) {
        browserController.find(text: text, forward: forward, matchCase: matchCase, findNext: findNext)
    }

    func stopFinding(clearSelection: Bool) {
        browserController.stopFinding(clearSelection: clearSelection)
    }

    func pageContentContext() async -> PageContentContext? {
        let currentTitle = displayTitle
        let currentURLString = urlString

        let extracted = await withCheckedContinuation { continuation in
            browserController.extractPageContent { selectedText, bodyText in
                continuation.resume(returning: (selectedText, bodyText))
            }
        }

        let context = PageContentContext(
            title: currentTitle,
            urlString: currentURLString,
            selectedText: extracted.0,
            bodyText: extracted.1
        )
        return context.preferredText == nil ? nil : context
    }

    func closeBrowser() {
        browserController.closeBrowser()
    }

    func closeBrowserForWindowClose() {
        browserController.closeBrowserForWindowClose()
    }

    func resetForLastPageClose(to urlString: String) {
        faviconFetchTask?.cancel()
        faviconFetchTask = nil
        loadedFaviconURL = nil
        favicon = nil
        title = "New Page"
        isLoading = false
        canGoBack = false
        canGoForward = false
        self.urlString = urlString
        browserController.stopFinding(clearSelection: true)
        browserController.navigate(toURLString: urlString)
    }
}

private final class BrowserPageSessionObserver: NSObject, TungstenBrowserControllerDelegate {
    weak var pageSession: BrowserPageSession?

    init(pageSession: BrowserPageSession) {
        self.pageSession = pageSession
    }

    func browserController(_ controller: TungstenBrowserController, didUpdateTitle title: String) {
        Task { @MainActor [weak pageSession] in
            pageSession?.updateTitle(title)
        }
    }

    func browserController(_ controller: TungstenBrowserController, didUpdateURL urlString: String) {
        Task { @MainActor [weak pageSession] in
            pageSession?.updateURL(urlString)
        }
    }

    func browserController(_ controller: TungstenBrowserController, didUpdateLoading isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        Task { @MainActor [weak pageSession] in
            pageSession?.isLoading = isLoading
            pageSession?.canGoBack = canGoBack
            pageSession?.canGoForward = canGoForward
        }
    }

    func browserController(_ controller: TungstenBrowserController, didUpdateFaviconURLs faviconURLs: [String]) {
        Task { @MainActor [weak pageSession] in
            pageSession?.updateFavicon(from: faviconURLs)
        }
    }

}

actor FaviconLoader {
    static let shared = FaviconLoader()

    private var cache: [String: NSImage] = [:]
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)
    }

    func image(for urlString: String) async -> NSImage? {
        if let cached = cache[urlString] {
            return cached
        }
        guard let url = URL(string: urlString) else {
            return nil
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let image = NSImage(data: data), image.isValid else {
                return nil
            }
            cache[urlString] = image
            return image
        } catch {
            return nil
        }
    }
}
