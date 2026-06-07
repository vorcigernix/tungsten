import Foundation

@Observable @MainActor
final class TungstenAppModel {
    let shortcutManager: ShortcutManager
    let historyStore: HistoryStore
    let appPreferences: AppPreferences

    @ObservationIgnored private let windowSessionCoordinator: BrowserWindowSessionCoordinator

    init(
        shortcutManager: ShortcutManager = ShortcutManager(),
        historyStore: HistoryStore = HistoryStore(),
        appPreferences: AppPreferences = AppPreferences(),
        windowSessionCoordinator: BrowserWindowSessionCoordinator = BrowserWindowSessionCoordinator()
    ) {
        self.shortcutManager = shortcutManager
        self.historyStore = historyStore
        self.appPreferences = appPreferences
        self.windowSessionCoordinator = windowSessionCoordinator
    }

    func makeBrowserWindowModel(kind: BrowserWindowKind) -> BrowserWindowModel {
        let prewarmStart = BrowserPerformanceLog.now()
        TungstenCEFApp.shared().prewarmCEF()
        BrowserPerformanceLog.duration("browserWindow.prewarmCEF.end", from: prewarmStart, metadata: [
            "kind": kind.sceneID
        ])

        let tabStore = windowSessionCoordinator.makeTabStore(kind: kind)

        return BrowserWindowModel(
            kind: kind,
            historyStore: historyStore,
            appPreferences: appPreferences,
            tabStore: tabStore,
            windowSessionCoordinator: windowSessionCoordinator
        )
    }
}

