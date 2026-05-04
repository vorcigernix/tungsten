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
    var selectedTabID: BrowserTab.ID?
    var addressText: String = ""

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

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
        }
        self.urlString = urlString
        browserController.navigate(toURLString: urlString)
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
