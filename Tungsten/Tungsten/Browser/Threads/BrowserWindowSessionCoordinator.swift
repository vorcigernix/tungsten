import Foundation

@Observable @MainActor
final class BrowserWindowSessionCoordinator {
    private let userDefaults: UserDefaults
    private var activeNormalWindowSessionIDs: Set<String> = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func makeThreadStore(kind: BrowserWindowKind) -> BrowserThreadStore {
        guard kind.isIncognito == false else {
            return BrowserThreadStore(userDefaults: userDefaults, scope: .memoryOnly)
        }

        let windowSessionID: String
        if activeNormalWindowSessionIDs.isEmpty {
            windowSessionID = BrowserThreadStore.mostRecentWindowSessionID(userDefaults: userDefaults)
                ?? BrowserThreadStore.makeWindowSessionID()
        } else {
            windowSessionID = BrowserThreadStore.makeWindowSessionID()
        }

        activeNormalWindowSessionIDs.insert(windowSessionID)
        BrowserThreadStore.markWindowSessionActive(windowSessionID, userDefaults: userDefaults)

        return BrowserThreadStore(
            userDefaults: userDefaults,
            scope: .persistent(windowSessionID: windowSessionID)
        )
    }

    func releaseThreadStore(_ threadStore: BrowserThreadStore, kind: BrowserWindowKind) {
        guard kind.isIncognito == false,
              let windowSessionID = threadStore.persistentWindowSessionID else {
            return
        }

        activeNormalWindowSessionIDs.remove(windowSessionID)
    }
}
