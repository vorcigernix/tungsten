/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Browser tab state and navigation actions.
*/

import AppKit
import Foundation

@Observable @MainActor
final class BrowserModel {
    var tabs: [BrowserTab] = []
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
    var findText = ""
    var findFocusRequestID = 0

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    private var previousSelectedTabID: BrowserTab.ID?

    init() {
        addTab(navigateTo: "https://www.google.com")
    }

    func addTab(navigateTo urlString: String = "https://www.google.com") {
        let tab = BrowserTab(initialURL: urlString)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else {
            return
        }

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
            let target = AddressResolver.navigationTarget(for: addressText),
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
}

@Observable @MainActor
final class BrowserTab: Identifiable {
    typealias ID = UUID

    let id = UUID()
    var title = "New Tab"
    var urlString: String
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var favicon: NSImage?
    var pageBackgroundColor: NSColor?

    @ObservationIgnored private var loadedFaviconURL: String?
    @ObservationIgnored private var faviconFetchTask: Task<Void, Never>?

    @ObservationIgnored private let initialURL: String
    @ObservationIgnored private lazy var observer = BrowserControllerObserver(tab: self)
    @ObservationIgnored lazy var browserController: TungstenBrowserController = {
        let controller = TungstenBrowserController(initialURL: initialURL)
        controller.delegate = observer
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

    init(initialURL: String) {
        self.initialURL = initialURL
        self.urlString = initialURL
    }

    func navigate(to urlString: String) {
        if URLComponents(string: urlString)?.host != URLComponents(string: self.urlString)?.host {
            favicon = nil
            loadedFaviconURL = nil
            pageBackgroundColor = nil
        }
        self.urlString = urlString
        browserController.navigate(toURLString: urlString)
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
}

private final class BrowserControllerObserver: NSObject, TungstenBrowserControllerDelegate {
    weak var tab: BrowserTab?

    init(tab: BrowserTab) {
        self.tab = tab
    }

    func browserController(_ controller: TungstenBrowserController, didUpdateTitle title: String) {
        Task { @MainActor [weak tab] in
            tab?.title = title
        }
    }

    func browserController(_ controller: TungstenBrowserController, didUpdateURL urlString: String) {
        Task { @MainActor [weak tab] in
            tab?.urlString = urlString
        }
    }

    func browserController(_ controller: TungstenBrowserController, didUpdateLoading isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        Task { @MainActor [weak tab] in
            tab?.isLoading = isLoading
            tab?.canGoBack = canGoBack
            tab?.canGoForward = canGoForward
        }
    }

    func browserController(_ controller: TungstenBrowserController, didUpdateFaviconURLs faviconURLs: [String]) {
        Task { @MainActor [weak tab] in
            tab?.updateFavicon(from: faviconURLs)
        }
    }

    func browserController(_ controller: TungstenBrowserController, didUpdatePageBackgroundColorString colorString: String) {
        Task { @MainActor [weak tab] in
            tab?.updatePageBackgroundColor(from: colorString)
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

        // rgba(0,0,0,0) is the default for "transparent" body backgrounds —
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
