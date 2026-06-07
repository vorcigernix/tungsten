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
                Toggle("Block third-party cookies", isOn: $appPreferences.thirdPartyCookieBlockingEnabled)

                Text("Stops most cross-site cookies in Chromium. Some embedded login and support widgets may need a site exception later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Prevent WebRTC IP leaks", isOn: $appPreferences.webRTCIPLeakProtectionEnabled)

                Text("Restricts WebRTC to avoid exposing local network routes. Video-call sites may behave differently.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Reduce fingerprinting surface", isOn: $appPreferences.fingerprintSurfaceReductionEnabled)

                Text("Blocks uncommon high-entropy browser signals like local font enumeration, sensors, idle detection, notification prompts, and ad attribution APIs while keeping normal web features on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("uBlock-style content blocking", isOn: $appPreferences.contentBlockingEnabled)

                Text("Blocks common ad and tracker requests in Chromium. Off by default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Advanced privacy") {
                    Toggle("Disable WebGL", isOn: $appPreferences.webGLDisabled)

                    Toggle("Disable remote fonts", isOn: $appPreferences.remoteFontsDisabled)

                    Toggle("Block JavaScript clipboard access", isOn: $appPreferences.javaScriptClipboardAccessDisabled)

                    Toggle("Disable local storage", isOn: $appPreferences.localStorageDisabled)

                    Text("These settings reduce fingerprinting and storage surfaces, but can break maps, editors, media tools, icons, sign-in flows, and web apps.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Privacy")
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
        .frame(width: 760, height: 640)
    }
}
