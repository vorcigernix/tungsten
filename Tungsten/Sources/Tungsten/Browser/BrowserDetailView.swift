/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The active page session's browser surface.
*/

import SwiftUI

struct BrowserDetailView: View {
    let pageSession: BrowserPageSession

    var body: some View {
        // The card's inset + position is owned by `BrowserSplitView`; here the
        // web view simply fills the card. Rounded corners come from the CEF
        // view's own layer (`cornerRadius`), since a SwiftUI `clipShape` can't
        // clip the hosted AppKit/CEF surface.
        BrowserView(controller: pageSession.browserController)
            .id(pageSession.tabID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(removing: .title)
    }
}

private struct BrowserView: NSViewRepresentable {
    let controller: TungstenBrowserController

    func makeNSView(context: Context) -> NSView {
        controller.cornerRadius = ChromeMetrics.cardCornerRadius
        return controller.view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.layoutBrowserView()
    }
}
