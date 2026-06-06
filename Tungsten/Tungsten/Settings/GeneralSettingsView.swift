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

                Picker("Address-bar answers", selection: $appPreferences.addressBarAIProvider) {
                    ForEach(AddressBarAIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                Text("Used when the address bar receives a natural-language question. Prefix with search to force a regular search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Search")
            }

            Section {
                Toggle("uBlock-style content blocking", isOn: $appPreferences.contentBlockingEnabled)

                Text("Blocks common ad and tracker requests in Chromium. Off by default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Content Blocking")
            }

            Section {
                Toggle("Start Arti for Tor tabs", isOn: $appPreferences.torLaunchesArti)

                TextField("Arti executable", text: $appPreferences.torArtiExecutablePath)
                    .textFieldStyle(.roundedBorder)

                TextField("SOCKS port", value: $appPreferences.torSocksPort, format: .number)
                    .textFieldStyle(.roundedBorder)

                Text("Tor tabs use a separate Chromium context routed through SOCKS5 on 127.0.0.1. Install Arti or point Tungsten at an existing compatible proxy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Tor")
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
