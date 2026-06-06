import AppKit
import Foundation

enum BrowserTabLayout: String, CaseIterable, Codable, Identifiable {
    case compact
    case separate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact:
            return "Compact"
        case .separate:
            return "Separate"
        }
    }
}

@Observable @MainActor
final class AppPreferences {
    @ObservationIgnored private let userDefaults: UserDefaults

    private static let searchEngineKey = "Tungsten.SearchEngine.v1"
    private static let tabLayoutKey = "Tungsten.BrowserTabLayout.v1"
    private static let transparencyEnabledKey = "Tungsten.WindowTransparencyEnabled.v1"
    private static let assistantProviderKey = "Tungsten.AssistantProvider.v1"
    private static let codexACPConfigurationKey = "Tungsten.ACP.CodexConfiguration.v1"
    private static let claudeACPConfigurationKey = "Tungsten.ACP.ClaudeConfiguration.v1"
    private static let localAIProviderKey = TungstenLocalAIProviderDefaultsKey

    var searchEngine: SearchEngine {
        didSet {
            guard oldValue != searchEngine else { return }
            userDefaults.set(searchEngine.rawValue, forKey: Self.searchEngineKey)
        }
    }

    var tabLayout: BrowserTabLayout {
        didSet {
            guard oldValue != tabLayout else { return }
            userDefaults.set(tabLayout.rawValue, forKey: Self.tabLayoutKey)
        }
    }

    var transparencyEnabled: Bool {
        didSet {
            guard oldValue != transparencyEnabled else { return }
            userDefaults.set(transparencyEnabled, forKey: Self.transparencyEnabledKey)
        }
    }

    var localAIProvider: LocalAIProvider {
        didSet {
            guard oldValue != localAIProvider else { return }
            userDefaults.set(localAIProvider.rawValue, forKey: Self.localAIProviderKey)
        }
    }

    var assistantProvider: SidebarAssistantProvider {
        didSet {
            guard oldValue != assistantProvider else { return }
            userDefaults.set(assistantProvider.rawValue, forKey: Self.assistantProviderKey)
            if let localAIProvider = assistantProvider.localAIProvider {
                self.localAIProvider = localAIProvider
            }
        }
    }

    var codexACPConfiguration: ACPProviderConfiguration {
        didSet {
            guard oldValue != codexACPConfiguration else { return }
            persistACPConfiguration(codexACPConfiguration, key: Self.codexACPConfigurationKey)
        }
    }

    var claudeACPConfiguration: ACPProviderConfiguration {
        didSet {
            guard oldValue != claudeACPConfiguration else { return }
            persistACPConfiguration(claudeACPConfiguration, key: Self.claudeACPConfigurationKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let raw = userDefaults.string(forKey: Self.searchEngineKey),
           let stored = SearchEngine(rawValue: raw) {
            self.searchEngine = stored
        } else {
            self.searchEngine = .duckDuckGo
        }

        if let raw = userDefaults.string(forKey: Self.searchEngineKey),
           ["googleAIMode", "perplexity", "duckAI"].contains(raw) {
            self.searchEngine = .duckDuckGo
            userDefaults.set(SearchEngine.duckDuckGo.rawValue, forKey: Self.searchEngineKey)
        }

        if let raw = userDefaults.string(forKey: Self.tabLayoutKey),
           let stored = BrowserTabLayout(rawValue: raw) {
            self.tabLayout = stored
        } else {
            self.tabLayout = .separate
        }

        if userDefaults.object(forKey: Self.transparencyEnabledKey) == nil {
            self.transparencyEnabled = true
        } else {
            self.transparencyEnabled = userDefaults.bool(forKey: Self.transparencyEnabledKey)
        }

        let resolvedLocalAIProvider: LocalAIProvider
        if let raw = userDefaults.string(forKey: Self.localAIProviderKey) {
            if raw == "google" {
                resolvedLocalAIProvider = .gemma
                userDefaults.set(LocalAIProvider.gemma.rawValue, forKey: Self.localAIProviderKey)
            } else if let stored = LocalAIProvider(rawValue: raw) {
                resolvedLocalAIProvider = stored
            } else {
                resolvedLocalAIProvider = .apple
            }
        } else {
            resolvedLocalAIProvider = .apple
        }
        self.localAIProvider = resolvedLocalAIProvider

        if let raw = userDefaults.string(forKey: Self.assistantProviderKey),
           let stored = SidebarAssistantProvider(rawValue: raw) {
            self.assistantProvider = stored
        } else {
            self.assistantProvider = .disabled
        }

        self.codexACPConfiguration = Self.loadACPConfiguration(
            from: userDefaults,
            key: Self.codexACPConfigurationKey,
            fallback: .codexDefault
        ).migratingLegacyCodexACPDefault()
        self.claudeACPConfiguration = Self.loadACPConfiguration(
            from: userDefaults,
            key: Self.claudeACPConfigurationKey,
            fallback: .claudeDefault
        )
    }

    private func persistACPConfiguration(_ configuration: ACPProviderConfiguration, key: String) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }
        userDefaults.set(data, forKey: key)
    }

    private static func loadACPConfiguration(
        from userDefaults: UserDefaults,
        key: String,
        fallback: ACPProviderConfiguration
    ) -> ACPProviderConfiguration {
        guard let data = userDefaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(ACPProviderConfiguration.self, from: data) else {
            return fallback
        }
        return configuration
    }

    /// Solid window backing color used when transparency is disabled. Adapts
    /// to the current macOS appearance: warm light taupe in Light mode, warm
    /// dark gray in Dark mode. The two values approximate
    /// `oklch(71.4% 0.014 41.2)` and `oklch(37.4% 0.01 67.558)` converted to
    /// sRGB, and are wrapped in a dynamic `NSColor` so the window picks the
    /// right one when the user toggles appearance.
    static let opaqueWindowBackgroundColor: NSColor = NSColor(name: "TungstenOpaqueWindow") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
        if isDark {
            return NSColor(srgbRed: 68.0 / 255.0, green: 64.0 / 255.0, blue: 59.0 / 255.0, alpha: 1)
        } else {
            return NSColor(srgbRed: 171.0 / 255.0, green: 160.0 / 255.0, blue: 156.0 / 255.0, alpha: 1)
        }
    }
}

private extension ACPProviderConfiguration {
    func migratingLegacyCodexACPDefault() -> ACPProviderConfiguration {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCommand == "codex", arguments == ["acp"] {
            return .codexDefault
        }
        return self
    }
}
