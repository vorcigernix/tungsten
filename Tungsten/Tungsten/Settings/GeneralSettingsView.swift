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

                Text("Used for new tabs and address-bar searches that aren't direct URLs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Search")
            }

            Section {
                Picker("Local AI", selection: $appPreferences.localAIProvider) {
                    ForEach(LocalAIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                Text("Google enables Chromium's local Gemini Nano prompt flags on next launch. Apple Local AI and Disabled keep those Chromium local model flags off.")
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
