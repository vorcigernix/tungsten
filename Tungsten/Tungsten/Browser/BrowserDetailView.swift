/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The selected tab's browser surface.
*/

import SwiftUI

struct BrowserDetailView: View {
    let tab: BrowserTab

    var body: some View {
        BrowserView(controller: tab.browserController)
            .id(tab.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Match the small transparent gutter the sidebar's rounded glass
            // panel has on all sides. The padding shows through to the
            // (transparent) window background, giving the page a floating
            // card look consistent with the sidebar.
            .padding(6)
            .ignoresSafeArea(edges: [.top, .bottom])
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

private struct BrowserView: NSViewRepresentable {
    let controller: TungstenBrowserController

    func makeNSView(context: Context) -> NSView {
        // Round the CEF NSView's CALayer so the page itself is clipped to
        // the rounded shape — SwiftUI's clipShape doesn't apply to AppKit
        // subviews, so this has to be done at the layer level.
        controller.cornerRadius = 12
        return controller.view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.layoutBrowserView()
    }
}
