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

                Text("Used for new threads and address-bar searches that aren't direct URLs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Search")
            }

            Section {
                Picker("AI behavior", selection: $appPreferences.localAIProvider) {
                    ForEach(LocalAIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                Text("Sidebar answers use Apple Local AI when available. Google Gemini Nano enables Chromium page AI flags on next launch; Disabled turns sidebar local answers and Chromium local model flags off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI")
            }

            Section {
                Toggle("Translucent window", isOn: $appPreferences.transparencyEnabled)

                Text("Disable to use a solid warm backdrop and skip window-level frosted blur. Disabling can improve launch and rendering responsiveness on older Macs.")
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
