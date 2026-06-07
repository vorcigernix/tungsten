import Foundation

@Observable @MainActor
final class BrowserWindowSessionCoordinator {
    private let userDefaults: UserDefaults
    private var activeNormalWindowSessionIDs: Set<String> = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func makeTabStore(kind: BrowserWindowKind) -> BrowserTabStore {
        guard kind.isIncognito == false else {
            return BrowserTabStore(userDefaults: userDefaults, scope: .memoryOnly)
        }

        let windowSessionID: String
        if activeNormalWindowSessionIDs.isEmpty {
            windowSessionID = BrowserTabStore.mostRecentWindowSessionID(userDefaults: userDefaults)
                ?? BrowserTabStore.makeWindowSessionID()
        } else {
            windowSessionID = BrowserTabStore.makeWindowSessionID()
        }

        activeNormalWindowSessionIDs.insert(windowSessionID)
        BrowserTabStore.markWindowSessionActive(windowSessionID, userDefaults: userDefaults)

        return BrowserTabStore(
            userDefaults: userDefaults,
            scope: .persistent(windowSessionID: windowSessionID)
        )
    }

    func releaseTabStore(_ tabStore: BrowserTabStore, kind: BrowserWindowKind) {
        guard kind.isIncognito == false,
              let windowSessionID = tabStore.persistentWindowSessionID else {
            return
        }

        activeNormalWindowSessionIDs.remove(windowSessionID)
    }
}
