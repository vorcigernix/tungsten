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
    var pageBackgroundColor: NSColor?

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

        return "New Tab"
    }

    init(pageTurnID: BrowserTurn.ID, initialURL: String, title: String = "New Page", isIncognito: Bool) {
        self.pageTurnID = pageTurnID
        self.initialURL = initialURL
        self.isIncognito = isIncognito
        self.urlString = initialURL
        self.title = title
    }

    convenience init(initialURL: String, isIncognito: Bool) {
        self.init(pageTurnID: BrowserTurn.ID(), initialURL: initialURL, title: "New Tab", isIncognito: isIncognito)
    }

    func navigate(to urlString: String) {
        if URLComponents(string: urlString)?.host != URLComponents(string: self.urlString)?.host {
            favicon = nil
            loadedFaviconURL = nil
            pageBackgroundColor = nil
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

    func updatePageBackgroundColor(from cssString: String) {
        pageBackgroundColor = NSColor.parseCSS(cssString)
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

    func closeBrowser() {
        browserController.closeBrowser()
    }

    func closeBrowserForWindowClose() {
        browserController.closeBrowserForWindowClose()
    }

    func resetForLastTabClose(to urlString: String) {
        faviconFetchTask?.cancel()
        faviconFetchTask = nil
        loadedFaviconURL = nil
        favicon = nil
        pageBackgroundColor = nil
        title = "New Tab"
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

    func browserController(_ controller: TungstenBrowserController, didUpdatePageBackgroundColorString colorString: String) {
        Task { @MainActor [weak pageSession] in
            pageSession?.updatePageBackgroundColor(from: colorString)
        }
    }
}

private extension NSColor {
    /// Parses CSS-style color strings produced by `getComputedStyle(...)`,
    /// which always normalizes to `rgb(r, g, b)` or `rgba(r, g, b, a)`.
    /// Returns nil for transparent or unrecognized values.
    static func parseCSS(_ raw: String) -> NSColor? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "transparent" {
            return nil
        }

        // Strip the leading "rgb(" / "rgba(" and trailing ")" then split on commas.
        guard let openParen = trimmed.firstIndex(of: "("),
              let closeParen = trimmed.lastIndex(of: ")") else {
            return nil
        }
        let prefix = trimmed[..<openParen].lowercased()
        guard prefix == "rgb" || prefix == "rgba" else {
            return nil
        }

        let inner = trimmed[trimmed.index(after: openParen)..<closeParen]
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else {
            return nil
        }

        guard let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]) else {
            return nil
        }
        let a: Double = parts.count == 4 ? (Double(parts[3]) ?? 1) : 1

        // rgba(0,0,0,0) is the default for "transparent" body backgrounds;
        // treat as no tint so the sidebar falls back to the system look.
        if a <= 0 {
            return nil
        }

        return NSColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
    }
}

private actor FaviconLoader {
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
