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
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("")
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
