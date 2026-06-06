/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The Liquid Glass browser chrome: one continuous glass bar hosting the
toolbar controls, address field, and tab strip.
*/

import AppKit
import SwiftUI

/// One continuous Liquid Glass bar that hosts the toolbar (and, in the
/// `.separate` layout, the tab strip). A single glass surface — controls live
/// *on* it as plain views, so there is no glass-on-glass.
struct BrowserChrome: View {
    let tabLayout: BrowserTabLayout

    var body: some View {
        VStack(spacing: 0) {
            ChromeBar(tabLayout: tabLayout)

            if tabLayout == .separate {
                SeparateTabBar()
            }
        }
        .frame(height: ChromeMetrics.totalHeight(for: tabLayout), alignment: .top)
        .glassEffect(.regular, in: Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
        .ignoresSafeArea(edges: .top)
    }
}

private struct ChromeBar: View {
    let tabLayout: BrowserTabLayout

    var body: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: ChromeMetrics.trafficLightGutter)

            SidebarHistoryMenu()
            NavigationControls()

            Spacer(minLength: 16)

            if tabLayout == .compact {
                CompactTabStrip()
                    .frame(minWidth: 360, idealWidth: 620, maxWidth: 820)
            } else {
                AddressBarField()
                    .frame(minWidth: 320, idealWidth: 560, maxWidth: 720)
            }

            Spacer(minLength: 16)

            ToolbarActions()
            PrivateWindowIndicator()
        }
        .padding(.horizontal, 12)
        .frame(height: ChromeMetrics.barHeight)
    }
}

// MARK: - Controls

/// Plain icon button used throughout the chrome. Foreground tracks state with
/// semantic colors; hover paints a subtle system fill (no nested glass).
private struct ChromeIconButton: View {
    let title: String
    let systemImage: String
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: ChromeMetrics.iconSize, weight: .medium))
                .frame(width: 30, height: ChromeMetrics.controlHeight)
                .contentShape(RoundedRectangle(cornerRadius: ChromeMetrics.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background {
            if isHovering && isEnabled {
                RoundedRectangle(cornerRadius: ChromeMetrics.controlCornerRadius, style: .continuous)
                    .fill(.quaternary)
            }
        }
        .disabled(isEnabled == false)
        .onHover { isHovering = $0 }
        .help(title)
    }

    private var foreground: AnyShapeStyle {
        if isEnabled == false {
            return AnyShapeStyle(.tertiary)
        }
        return AnyShapeStyle(isHovering ? .primary : .secondary)
    }
}

private struct SidebarHistoryMenu: View {
    @Environment(BrowserModel.self) private var browserModel
    @State private var isHovering = false

    var body: some View {
        Menu {
            Button("Show History", systemImage: "clock.arrow.circlepath") {
                browserModel.showHistory()
            }
            Button("Copy URL", systemImage: "doc.on.doc") {
                browserModel.copyActivePageURL()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: ChromeMetrics.iconSize, weight: .medium))
                .frame(width: 30, height: ChromeMetrics.controlHeight)
                .contentShape(RoundedRectangle(cornerRadius: ChromeMetrics.controlCornerRadius, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: ChromeMetrics.controlCornerRadius, style: .continuous)
                    .fill(.quaternary)
            }
        }
        .onHover { isHovering = $0 }
        .help("Sidebar and History")
    }
}

private struct NavigationControls: View {
    @Environment(BrowserModel.self) private var browserModel

    var body: some View {
        let pageSession = browserModel.activePageSession

        HStack(spacing: 2) {
            ChromeIconButton(
                title: "Back",
                systemImage: "chevron.backward",
                isEnabled: pageSession?.canGoBack == true
            ) {
                pageSession?.goBack()
            }

            ChromeIconButton(
                title: "Forward",
                systemImage: "chevron.forward",
                isEnabled: pageSession?.canGoForward == true
            ) {
                pageSession?.goForward()
            }
        }
    }
}

private struct ToolbarActions: View {
    @Environment(BrowserModel.self) private var browserModel

    var body: some View {
        HStack(spacing: 2) {
            ChromeIconButton(title: "Share", systemImage: "square.and.arrow.up") {
                browserModel.copyActivePageURL()
            }

            ChromeIconButton(title: "New Tab", systemImage: "plus") {
                browserModel.createTab()
            }

            ChromeIconButton(title: "Show History", systemImage: "clock.arrow.circlepath") {
                browserModel.showHistory()
            }
        }
    }
}

private struct PrivateWindowIndicator: View {
    @Environment(BrowserModel.self) private var browserModel

    var body: some View {
        if browserModel.kind.isIncognito {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: ChromeMetrics.iconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
                .help("Private Window")
        }
    }
}

// MARK: - Address field

private struct AddressBarField: View {
    @Environment(BrowserModel.self) private var browserModel
    var compact = false
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var browserModel = browserModel
        let pageSession = browserModel.activePageSession
        let isPageLoading = pageSession?.isLoading == true

        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: ChromeMetrics.smallIconSize, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search or enter website name", text: $browserModel.addressText)
                .textFieldStyle(.plain)
                .font(.system(size: compact ? ChromeMetrics.compactFontSize : ChromeMetrics.bodyFontSize))
                .foregroundStyle(.primary)
                .focused($isFocused)
                .onSubmit {
                    browserModel.submitAddressBar()
                }

            if pageSession != nil {
                Button {
                    if isPageLoading {
                        pageSession?.stopLoading()
                    } else {
                        pageSession?.reload()
                    }
                } label: {
                    Image(systemName: isPageLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: ChromeMetrics.smallIconSize, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(isPageLoading ? "Stop" : "Reload")
                .help(isPageLoading ? "Stop" : "Reload")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: ChromeMetrics.controlHeight)
        .background {
            Capsule(style: .continuous)
                .fill(.quaternary)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isFocused ? 2 : 0)
        }
        .onChange(of: browserModel.addressFocusRequestID) { _, _ in
            isFocused = true
        }
    }
}

// MARK: - Tabs

private struct CompactTabStrip: View {
    @Environment(BrowserModel.self) private var browserModel

    var body: some View {
        @Bindable var browserModel = browserModel

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(browserModel.tabs) { tab in
                    if tab.id == browserModel.selectedTabID {
                        AddressTab(tab: tab)
                            .frame(minWidth: 320, idealWidth: 460, maxWidth: 560)
                    } else {
                        TabButton(
                            tab: tab,
                            isSelected: false,
                            onSelect: { browserModel.selectedTabID = tab.id }
                        )
                        .frame(width: tab.isPinned ? 40 : 160)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct SeparateTabBar: View {
    var body: some View {
        TabStrip()
            .padding(.horizontal, 12)
            .frame(height: ChromeMetrics.tabBarHeight)
    }
}

private struct TabStrip: View {
    @Environment(BrowserModel.self) private var browserModel

    var body: some View {
        @Bindable var browserModel = browserModel

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(browserModel.tabs) { tab in
                    TabButton(
                        tab: tab,
                        isSelected: tab.id == browserModel.selectedTabID,
                        onSelect: { browserModel.selectedTabID = tab.id }
                    )
                    .frame(width: tab.isPinned ? 44 : 220)
                }
            }
        }
        .frame(height: ChromeMetrics.tabBarHeight)
    }
}

private struct AddressTab: View {
    let tab: BrowserTab

    var body: some View {
        HStack(spacing: 7) {
            TabFavicon(tab: tab)
            AddressBarField(compact: true)
            CloseTabButton(tab: tab, isSelected: true)
        }
        .padding(.horizontal, 4)
        .frame(height: ChromeMetrics.tabHeight)
        .contextMenu {
            TabContextMenu(tab: tab)
        }
    }
}

private struct TabButton: View {
    let tab: BrowserTab
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    TabFavicon(tab: tab)

                    if tab.isPinned == false {
                        Text(tab.displayTitle)
                            .font(.system(size: ChromeMetrics.bodyFontSize, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, tab.isPinned ? 0 : 8)
                .padding(.trailing, tab.isPinned ? 0 : 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tab.isPinned ? .center : .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if tab.isPinned == false {
                CloseTabButton(tab: tab, isSelected: isSelected)
                    .padding(.trailing, 5)
            }
        }
        .frame(height: ChromeMetrics.tabHeight)
        .background {
            tabBackground
        }
        .contextMenu {
            TabContextMenu(tab: tab)
        }
        .onHover { isHovering = $0 }
    }

    @ViewBuilder private var tabBackground: some View {
        if isSelected {
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                }
        } else if isHovering {
            Capsule(style: .continuous)
                .fill(.quaternary)
        }
    }
}

private struct TabFavicon: View {
    let tab: BrowserTab

    var body: some View {
        FaviconIcon(
            faviconURLString: tab.faviconURLString,
            fallbackSystemName: tab.urlString == nil ? "plus" : "globe",
            size: 15
        )
    }
}

private struct CloseTabButton: View {
    @Environment(BrowserModel.self) private var browserModel
    let tab: BrowserTab
    var isSelected: Bool = false

    @State private var isHovering = false

    var body: some View {
        Button("Close Tab", systemImage: "xmark") {
            browserModel.close(tab)
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 9, weight: .semibold))
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .opacity(isSelected || isHovering ? 1 : 0.55)
        .frame(width: 18, height: 18)
        .background {
            if isHovering {
                Circle().fill(.quaternary)
            }
        }
        .help("Close Tab")
        .onHover { isHovering = $0 }
    }
}

private struct TabContextMenu: View {
    @Environment(BrowserModel.self) private var browserModel
    let tab: BrowserTab

    var body: some View {
        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab", systemImage: tab.isPinned ? "pin.slash" : "pin") {
            browserModel.toggleTabPin(tab)
        }

        Button("Close Tab", systemImage: "xmark") {
            browserModel.close(tab)
        }

        Button("Close Other Tabs", systemImage: "rectangle.stack.badge.minus") {
            browserModel.closeOtherTabs(keeping: tab)
        }
        .disabled(browserModel.tabs.count <= 1)
    }
}
