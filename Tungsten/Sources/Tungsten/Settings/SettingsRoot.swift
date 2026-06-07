import SwiftUI

struct SettingsRoot: View {
    @Environment(TungstenAppModel.self) private var appModel

    var body: some View {
        TabView {
            GeneralSettingsView(appPreferences: appModel.appPreferences)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ShortcutSettingsView(shortcutManager: appModel.shortcutManager)
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
        }
    }
}
