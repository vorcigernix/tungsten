/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The active page session's browser surface.
*/

import SwiftUI

struct BrowserDetailView: View {
    let pageSession: BrowserPageSession
    /// Space reserved at the top for the floating glass chrome, so the web
    /// page begins below the bar instead of being occluded by it.
    var topInset: CGFloat = 0

    var body: some View {
        BrowserView(controller: pageSession.browserController)
            .id(pageSession.tabID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, topInset)
            .ignoresSafeArea(edges: [.top, .bottom])
            .toolbar(removing: .title)
    }
}

private struct BrowserView: NSViewRepresentable {
    let controller: TungstenBrowserController

    func makeNSView(context: Context) -> NSView {
        controller.cornerRadius = 0
        return controller.view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.layoutBrowserView()
    }
}
