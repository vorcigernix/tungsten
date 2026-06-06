import Foundation

@Observable @MainActor
final class BrowserWindowModel {
    let kind: BrowserWindowKind
    let browserModel: BrowserModel

    @ObservationIgnored private let tabStore: BrowserTabStore
    @ObservationIgnored private let windowSessionCoordinator: BrowserWindowSessionCoordinator
    @ObservationIgnored private var didReleaseTabStore = false

    init(
        kind: BrowserWindowKind,
        historyStore: HistoryStore,
        appPreferences: AppPreferences,
        tabStore: BrowserTabStore,
        windowSessionCoordinator: BrowserWindowSessionCoordinator
    ) {
        self.kind = kind
        self.tabStore = tabStore
        self.windowSessionCoordinator = windowSessionCoordinator
        self.browserModel = BrowserModel(
            kind: kind,
            historyStore: historyStore,
            appPreferences: appPreferences,
            tabStore: tabStore
        )
    }

    func releaseTabStoreIfNeeded() {
        guard didReleaseTabStore == false else {
            return
        }

        didReleaseTabStore = true
        windowSessionCoordinator.releaseTabStore(tabStore, kind: kind)
    }
}

