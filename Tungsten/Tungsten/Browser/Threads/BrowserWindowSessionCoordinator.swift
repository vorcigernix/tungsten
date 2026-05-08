import Foundation

@Observable @MainActor
final class BrowserWindowSessionCoordinator {
    private var didClaimInitialNormalSession = false

    func makeThreadStore(kind: BrowserWindowKind) -> BrowserThreadStore {
        guard kind.isIncognito == false else {
            return BrowserThreadStore(scope: .memoryOnly)
        }

        let windowSessionID: String
        if didClaimInitialNormalSession == false {
            didClaimInitialNormalSession = true
            windowSessionID = BrowserThreadStore.mostRecentWindowSessionID()
                ?? BrowserThreadStore.makeWindowSessionID()
        } else {
            windowSessionID = BrowserThreadStore.makeWindowSessionID()
        }

        BrowserThreadStore.markWindowSessionActive(windowSessionID)
        return BrowserThreadStore(scope: .persistent(windowSessionID: windowSessionID))
    }
}
