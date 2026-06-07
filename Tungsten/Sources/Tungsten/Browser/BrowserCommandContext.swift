import Foundation
import SwiftUI

@MainActor
struct BrowserCommandContext {
    let browserModel: BrowserModel
    let openNormalWindow: () -> Void
    let openIncognitoWindow: () -> Void
}

private struct BrowserCommandContextFocusedValueKey: FocusedValueKey {
    typealias Value = BrowserCommandContext
}

extension FocusedValues {
    var browserCommandContext: BrowserCommandContext? {
        get { self[BrowserCommandContextFocusedValueKey.self] }
        set { self[BrowserCommandContextFocusedValueKey.self] = newValue }
    }
}
