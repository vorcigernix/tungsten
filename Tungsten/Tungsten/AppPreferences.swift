import AppKit
import Foundation

@Observable @MainActor
final class AppPreferences {
    @ObservationIgnored private let userDefaults: UserDefaults

    private static let searchEngineKey = "Tungsten.SearchEngine.v1"
    private static let transparencyEnabledKey = "Tungsten.WindowTransparencyEnabled.v1"

    var searchEngine: SearchEngine {
        didSet {
            guard oldValue != searchEngine else { return }
            userDefaults.set(searchEngine.rawValue, forKey: Self.searchEngineKey)
        }
    }

    var transparencyEnabled: Bool {
        didSet {
            guard oldValue != transparencyEnabled else { return }
            userDefaults.set(transparencyEnabled, forKey: Self.transparencyEnabledKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let raw = userDefaults.string(forKey: Self.searchEngineKey),
           let stored = SearchEngine(rawValue: raw) {
            self.searchEngine = stored
        } else {
            self.searchEngine = .googleAIMode
        }

        if userDefaults.object(forKey: Self.transparencyEnabledKey) == nil {
            self.transparencyEnabled = true
        } else {
            self.transparencyEnabled = userDefaults.bool(forKey: Self.transparencyEnabledKey)
        }
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
