import SwiftUI

/// Single source of truth for browser-chrome dimensions.
///
/// Colors are intentionally *not* defined here. The chrome uses semantic
/// system colors (`.primary`, `.secondary`, `.tertiary`, `Color.accentColor`,
/// `NSColor.separatorColor`, system fills, …) so it adapts to light/dark, the
/// user's accent color, and accessibility settings automatically.
enum ChromeMetrics {
    /// Main toolbar row height. Compact single row with the traffic lights
    /// inline (Safari-style); the glass spans the full top.
    static let barHeight: CGFloat = 50
    /// Dedicated tab-strip height in the `.separate` layout.
    static let tabBarHeight: CGFloat = 38

    /// Interactive control height inside the bar (buttons, address field).
    static let controlHeight: CGFloat = 28
    /// Tab height.
    static let tabHeight: CGFloat = 28

    /// Address-field height when focused — it grows from `controlHeight` in
    /// place (same position, same corner radius), nothing else moves.
    static let expandedFieldHeight: CGFloat = 56
    /// Tab height when minimized to a thin bar (focused state) — the tab
    /// shrinks vertically, keeping its width.
    static let minimizedTabHeight: CGFloat = 12

    /// Leading inset that keeps chrome clear of the window traffic lights.
    static let trafficLightGutter: CGFloat = 78

    /// SF Symbol point size for bar controls.
    static let iconSize: CGFloat = 14
    static let smallIconSize: CGFloat = 11

    /// macOS body / compact text sizes.
    static let bodyFontSize: CGFloat = 13
    static let compactFontSize: CGFloat = 12

    /// Corner radius for control hover / selection fills.
    static let controlCornerRadius: CGFloat = 7

    /// Total chrome height for a given tab layout.
    static func totalHeight(for layout: BrowserTabLayout) -> CGFloat {
        layout == .separate ? barHeight + tabBarHeight : barHeight
    }
}
