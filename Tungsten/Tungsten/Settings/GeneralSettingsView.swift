import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var appPreferences: AppPreferences

    var body: some View {
        Form {
            Section {
                Picker("Search engine", selection: $appPreferences.searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.menu)

                Text("Used for address-bar searches and search keyword requests.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Search")
            }

            Section {
                Picker("Tab layout", selection: $appPreferences.tabLayout) {
                    ForEach(BrowserTabLayout.allCases) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
                .pickerStyle(.menu)

                Text("Compact keeps tabs and the Smart Search field in one row. Separate puts the Smart Search field above a dedicated tab strip.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Tabs")
            }

            Section {
                Toggle("Translucent window", isOn: $appPreferences.transparencyEnabled)

                Text("Controls whether Tungsten uses macOS translucent materials in browser chrome.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Appearance")
            }
        }
        .formStyle(.grouped)
        .frame(width: 760, height: 560)
    }
}
