/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The main browser app declaration.
*/

import AppKit
import SwiftUI

@main
struct TungstenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var browserModel = BrowserModel()
    @State private var shortcutManager = ShortcutManager()

    var body: some Scene {
        WindowGroup {
            BrowserSplitView()
                .environment(browserModel)
                .background(
                    ShortcutEventMonitor(
                        shortcutManager: shortcutManager,
                        browserModel: browserModel
                    )
                )
                .frame(minWidth: 700, minHeight: 460)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    browserModel.addTab()
                }
            }
        }

        Settings {
            ShortcutSettingsView(shortcutManager: shortcutManager)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else {
            return
        }

        NSApp.applicationIconImage = icon
    }

    func applicationWillTerminate(_ notification: Notification) {
        TungstenCEFApp.shared().shutdownCEF()
    }
}
