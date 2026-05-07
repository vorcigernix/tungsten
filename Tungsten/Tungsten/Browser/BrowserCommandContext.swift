import Foundation

@MainActor
struct BrowserCommandContext {
    let browserModel: BrowserModel
    let openNormalWindow: () -> Void
    let openIncognitoWindow: () -> Void
}
