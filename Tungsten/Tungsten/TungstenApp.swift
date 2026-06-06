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
    @State private var shortcutManager = ShortcutManager()
    @State private var historyStore = HistoryStore()
    @State private var appPreferences = AppPreferences()
    @State private var windowSessionCoordinator = BrowserWindowSessionCoordinator()

    var body: some Scene {
        WindowGroup(BrowserWindowKind.normal.title, id: BrowserWindowKind.normal.sceneID) {
            BrowserWindowRoot(
                kind: .normal,
                shortcutManager: shortcutManager,
                historyStore: historyStore,
                appPreferences: appPreferences,
                windowSessionCoordinator: windowSessionCoordinator
            )
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)

        WindowGroup(BrowserWindowKind.incognito.title, id: BrowserWindowKind.incognito.sceneID) {
            BrowserWindowRoot(
                kind: .incognito,
                shortcutManager: shortcutManager,
                historyStore: historyStore,
                appPreferences: appPreferences,
                windowSessionCoordinator: windowSessionCoordinator
            )
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsRoot(
                shortcutManager: shortcutManager,
                appPreferences: appPreferences
            )
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        installUncaughtExceptionLogger()
        DispatchQueue.main.async {
            TungstenCEFApp.shared().prewarmCEF()
        }

        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else {
            return
        }

        NSApp.applicationIconImage = icon
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        TungstenCEFApp.shared().beginTermination()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        TungstenCEFApp.shared().beginTermination()
        TungstenCEFApp.shared().shutdownCEF()
    }
}

/// Writes details of any uncaught Objective-C exception to
/// `~/Library/Logs/Tungsten-crashes.log` before the runtime terminates the
/// process. The default crash reporter logs the exception's *format string*
/// instead of expanding `%s`, so the actual selector and class are lost. By
/// resolving `NSException.reason` ourselves at the moment the exception is
/// created we capture the real selector name, which is what we need to
/// pinpoint the source of the CEF window-close crash.
private func installUncaughtExceptionLogger() {
    NSSetUncaughtExceptionHandler { exception in
        let path = (NSString(string: "~/Library/Logs/Tungsten-crashes.log") as NSString)
            .expandingTildeInPath
        let block = """

        =====
        [\(Date())] Uncaught exception
          name:    \(exception.name.rawValue)
          reason:  \(exception.reason ?? "(none)")
          userInfo:\(exception.userInfo.map { "\n    \($0)" } ?? " (none)")
          stack:
        \(exception.callStackSymbols.joined(separator: "\n"))

        """

        if let data = block.data(using: .utf8) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }

        NSLog("Tungsten uncaught exception: %@ — %@",
              exception.name.rawValue,
              exception.reason ?? "(no reason)")
    }
}
