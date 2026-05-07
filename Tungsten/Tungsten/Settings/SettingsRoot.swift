import SwiftUI

struct SettingsRoot: View {
    let shortcutManager: ShortcutManager
    let appPreferences: AppPreferences

    var body: some View {
        TabView {
            GeneralSettingsView(appPreferences: appPreferences)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ShortcutSettingsView(shortcutManager: shortcutManager)
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
        }
    }
}
