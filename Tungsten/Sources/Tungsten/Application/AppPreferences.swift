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
    private static let addressBarAIProviderKey = "Tungsten.AddressBarAIProvider.v1"
#if TESTING
    private static let localAIProviderKey = "Tungsten.LocalAIProvider.v1"
    private static let contentBlockingEnabledKey = "Tungsten.ContentBlockingEnabled.v1"
    private static let thirdPartyCookieBlockingEnabledKey = "Tungsten.Privacy.BlockThirdPartyCookies.v1"
    private static let webRTCIPLeakProtectionEnabledKey = "Tungsten.Privacy.WebRTCIPLeakProtection.v1"
    private static let fingerprintSurfaceReductionEnabledKey = "Tungsten.Privacy.FingerprintSurfaceReduction.v1"
    private static let webGLDisabledKey = "Tungsten.Privacy.DisableWebGL.v1"
    private static let remoteFontsDisabledKey = "Tungsten.Privacy.DisableRemoteFonts.v1"
    private static let javaScriptClipboardAccessDisabledKey = "Tungsten.Privacy.DisableJavaScriptClipboardAccess.v1"
    private static let localStorageDisabledKey = "Tungsten.Privacy.DisableLocalStorage.v1"
#else
    private static let localAIProviderKey = TungstenLocalAIProviderDefaultsKey
    private static let contentBlockingEnabledKey = TungstenContentBlockingEnabledDefaultsKey
    private static let thirdPartyCookieBlockingEnabledKey = TungstenThirdPartyCookieBlockingEnabledDefaultsKey
    private static let webRTCIPLeakProtectionEnabledKey = TungstenWebRTCIPLeakProtectionEnabledDefaultsKey
    private static let fingerprintSurfaceReductionEnabledKey = TungstenFingerprintSurfaceReductionEnabledDefaultsKey
    private static let webGLDisabledKey = TungstenWebGLDisabledDefaultsKey
    private static let remoteFontsDisabledKey = TungstenRemoteFontsDisabledDefaultsKey
    private static let javaScriptClipboardAccessDisabledKey = TungstenJavaScriptClipboardAccessDisabledDefaultsKey
    private static let localStorageDisabledKey = TungstenLocalStorageDisabledDefaultsKey
#endif
    private static let torLaunchesArtiKey = "Tungsten.Tor.LaunchesArti.v1"
    private static let torArtiExecutablePathKey = "Tungsten.Tor.ArtiExecutablePath.v1"
    private static let torSocksPortKey = "Tungsten.Tor.SocksPort.v1"

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

    var addressBarAIProvider: AddressBarAIProvider {
        didSet {
            guard oldValue != addressBarAIProvider else { return }
            userDefaults.set(addressBarAIProvider.rawValue, forKey: Self.addressBarAIProviderKey)
        }
    }

    var contentBlockingEnabled: Bool {
        didSet {
            guard oldValue != contentBlockingEnabled else { return }
            userDefaults.set(contentBlockingEnabled, forKey: Self.contentBlockingEnabledKey)
        }
    }

    var thirdPartyCookieBlockingEnabled: Bool {
        didSet {
            guard oldValue != thirdPartyCookieBlockingEnabled else { return }
            userDefaults.set(thirdPartyCookieBlockingEnabled, forKey: Self.thirdPartyCookieBlockingEnabledKey)
        }
    }

    var webRTCIPLeakProtectionEnabled: Bool {
        didSet {
            guard oldValue != webRTCIPLeakProtectionEnabled else { return }
            userDefaults.set(webRTCIPLeakProtectionEnabled, forKey: Self.webRTCIPLeakProtectionEnabledKey)
        }
    }

    var fingerprintSurfaceReductionEnabled: Bool {
        didSet {
            guard oldValue != fingerprintSurfaceReductionEnabled else { return }
            userDefaults.set(fingerprintSurfaceReductionEnabled, forKey: Self.fingerprintSurfaceReductionEnabledKey)
        }
    }

    var webGLDisabled: Bool {
        didSet {
            guard oldValue != webGLDisabled else { return }
            userDefaults.set(webGLDisabled, forKey: Self.webGLDisabledKey)
        }
    }

    var remoteFontsDisabled: Bool {
        didSet {
            guard oldValue != remoteFontsDisabled else { return }
            userDefaults.set(remoteFontsDisabled, forKey: Self.remoteFontsDisabledKey)
        }
    }

    var javaScriptClipboardAccessDisabled: Bool {
        didSet {
            guard oldValue != javaScriptClipboardAccessDisabled else { return }
            userDefaults.set(javaScriptClipboardAccessDisabled, forKey: Self.javaScriptClipboardAccessDisabledKey)
        }
    }

    var localStorageDisabled: Bool {
        didSet {
            guard oldValue != localStorageDisabled else { return }
            userDefaults.set(localStorageDisabled, forKey: Self.localStorageDisabledKey)
        }
    }

    var torLaunchesArti: Bool {
        didSet {
            guard oldValue != torLaunchesArti else { return }
            userDefaults.set(torLaunchesArti, forKey: Self.torLaunchesArtiKey)
        }
    }

    var torArtiExecutablePath: String {
        didSet {
            guard oldValue != torArtiExecutablePath else { return }
            userDefaults.set(torArtiExecutablePath, forKey: Self.torArtiExecutablePathKey)
        }
    }

    var torSocksPort: Int {
        didSet {
            let clampedPort = min(max(torSocksPort, 1), 65535)
            if torSocksPort != clampedPort {
                torSocksPort = clampedPort
            }
            guard oldValue != torSocksPort else { return }
            userDefaults.set(torSocksPort, forKey: Self.torSocksPortKey)
        }
    }

    var torConfiguration: TorProxyConfiguration {
        TorProxyConfiguration(
            launchesArti: torLaunchesArti,
            artiExecutablePath: torArtiExecutablePath,
            socksHost: TorProxyConfiguration.default.socksHost,
            socksPort: torSocksPort
        )
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
        let legacySearchEngineRaw = userDefaults.string(forKey: Self.searchEngineKey)

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

        if let raw = userDefaults.string(forKey: Self.addressBarAIProviderKey),
           let stored = AddressBarAIProvider(rawValue: raw) {
            self.addressBarAIProvider = stored
        } else if legacySearchEngineRaw == "googleAIMode" {
            self.addressBarAIProvider = .googleAI
            userDefaults.set(AddressBarAIProvider.googleAI.rawValue, forKey: Self.addressBarAIProviderKey)
        } else {
            self.addressBarAIProvider = .duckDuckGoAI
        }

        if userDefaults.object(forKey: Self.contentBlockingEnabledKey) == nil {
            self.contentBlockingEnabled = false
        } else {
            self.contentBlockingEnabled = userDefaults.bool(forKey: Self.contentBlockingEnabledKey)
        }

        if userDefaults.object(forKey: Self.thirdPartyCookieBlockingEnabledKey) == nil {
            self.thirdPartyCookieBlockingEnabled = true
        } else {
            self.thirdPartyCookieBlockingEnabled = userDefaults.bool(forKey: Self.thirdPartyCookieBlockingEnabledKey)
        }

        if userDefaults.object(forKey: Self.webRTCIPLeakProtectionEnabledKey) == nil {
            self.webRTCIPLeakProtectionEnabled = true
        } else {
            self.webRTCIPLeakProtectionEnabled = userDefaults.bool(forKey: Self.webRTCIPLeakProtectionEnabledKey)
        }

        if userDefaults.object(forKey: Self.fingerprintSurfaceReductionEnabledKey) == nil {
            self.fingerprintSurfaceReductionEnabled = true
        } else {
            self.fingerprintSurfaceReductionEnabled = userDefaults.bool(forKey: Self.fingerprintSurfaceReductionEnabledKey)
        }

        if userDefaults.object(forKey: Self.webGLDisabledKey) == nil {
            self.webGLDisabled = false
        } else {
            self.webGLDisabled = userDefaults.bool(forKey: Self.webGLDisabledKey)
        }

        if userDefaults.object(forKey: Self.remoteFontsDisabledKey) == nil {
            self.remoteFontsDisabled = false
        } else {
            self.remoteFontsDisabled = userDefaults.bool(forKey: Self.remoteFontsDisabledKey)
        }

        if userDefaults.object(forKey: Self.javaScriptClipboardAccessDisabledKey) == nil {
            self.javaScriptClipboardAccessDisabled = false
        } else {
            self.javaScriptClipboardAccessDisabled = userDefaults.bool(forKey: Self.javaScriptClipboardAccessDisabledKey)
        }

        if userDefaults.object(forKey: Self.localStorageDisabledKey) == nil {
            self.localStorageDisabled = false
        } else {
            self.localStorageDisabled = userDefaults.bool(forKey: Self.localStorageDisabledKey)
        }

        if userDefaults.object(forKey: Self.torLaunchesArtiKey) == nil {
            self.torLaunchesArti = TorProxyConfiguration.default.launchesArti
        } else {
            self.torLaunchesArti = userDefaults.bool(forKey: Self.torLaunchesArtiKey)
        }

        if let storedPath = userDefaults.string(forKey: Self.torArtiExecutablePathKey),
           storedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            self.torArtiExecutablePath = storedPath
        } else {
            self.torArtiExecutablePath = TorProxyConfiguration.default.artiExecutablePath
        }

        let storedTorPort = userDefaults.integer(forKey: Self.torSocksPortKey)
        if userDefaults.object(forKey: Self.torSocksPortKey) == nil {
            self.torSocksPort = TorProxyConfiguration.default.socksPort
        } else {
            self.torSocksPort = min(max(storedTorPort, 1), 65535)
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
