import Foundation

enum BrowserThreadStoreScope: Equatable {
    case persistent(windowSessionID: String)
    case memoryOnly
}
