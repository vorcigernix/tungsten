/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The Liquid Glass browser chrome. A single, stable layout: on focus the address
field simply grows taller in place and the tabs shrink into small favicon dots —
nothing else moves or changes shape.
*/

import AppKit
import SwiftUI

struct BrowserChrome: View {
    @Environment(BrowserModel.self) private var browserModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tabLayout: BrowserTabLayout

    @State private var isExpanded = false
    @FocusState private var fieldFocused: Bool
    @State private var collapseTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
                .zIndex(1)

            if tabLayout == .separate {
                TabStrip(onPickDot: { collapse() })
                    .padding(.horizontal, 12)
                    .frame(height: ChromeMetrics.tabBarHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .glassEffect(.regular, in: Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
        .ignoresSafeArea(edges: .top)
        .animation(expandAnimation, value: isExpanded)
        .onAppear { requestFocus() }
        .onChange(of: browserModel.addressFocusRequestID) { _, _ in requestFocus() }
        .onChange(of: fieldFocused) { _, focused in
            if focused {
                isExpanded = true
                startCollapseTimer()
            } else {
                collapse()
            }
        }
    }

    private var expandAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .smooth(duration: 0.32)
    }

    // The toolbar row keeps every control exactly where it is. Only the address
    // field changes height; controls stay pinned to the top band.
    private var toolbarRow: some View {
        // Collapsed: the field is centered in the bar. Focused: the field grows
        // taller with its top edge fixed, so the chrome grows and the full tab
        // strip rides down with it — the tabs themselves are left unchanged.
        let inset = (ChromeMetrics.barHeight - ChromeMetrics.controlHeight) / 2
        return HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                Color.clear.frame(width: ChromeMetrics.trafficLightGutter)
                SidebarHistoryMenu()
                NavigationControls()

                if tabLayout == .compact {
                    InlineTabStrip(onPickDot: { collapse() })
                }
            }
            .frame(height: ChromeMetrics.barHeight)

            AddressField(focused: $fieldFocused, onSubmit: { submit() })
                .frame(height: isExpanded ? ChromeMetrics.expandedFieldHeight : ChromeMetrics.controlHeight, alignment: .top)
                .padding(.top, inset)
                .frame(minWidth: 320, idealWidth: 560, maxWidth: 760)

            HStack(spacing: 2) {
                ToolbarActions()
                PrivateWindowIndicator()
            }
            .frame(height: ChromeMetrics.barHeight)
        }
        .padding(.horizontal, 12)
        .frame(height: isExpanded ? ChromeMetrics.expandedFieldHeight + inset * 2 : ChromeMetrics.barHeight, alignment: .top)
    }

    // MARK: - Expand / collapse

    private func requestFocus() {
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func collapse() {
        cancelCollapseTimer()
        guard isExpanded else { return }
        isExpanded = false
        fieldFocused = false
        browserModel.addressText = browserModel.selectedTab?.urlString ?? ""
    }

    private func submit() {
        browserModel.submitAddressBar()
        collapse()
    }

    // Collapses after the pointer has been outside the chrome for 10s, unless
    // the field still holds a draft being typed.
    private func startCollapseTimer() {
        cancelCollapseTimer()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard Task.isCancelled == false, isExpanded else { return }
            if fieldFocused && browserModel.addressText.isEmpty == false {
                startCollapseTimer()
            } else {
                collapse()
            }
        }
    }

    private func cancelCollapseTimer() {
        collapseTask?.cancel()
        collapseTask = nil
    }
}

// MARK: - Controls

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

// MARK: - Address field (grows vertically on focus, same place / shape)

private struct AddressField: View {
    @Environment(BrowserModel.self) private var browserModel
    @FocusState.Binding var focused: Bool
    let onSubmit: () -> Void
    @State private var didSelectTextForCurrentFocus = false

    var body: some View {
        @Bindable var browserModel = browserModel
        let pageSession = browserModel.activePageSession
        let isPageLoading = pageSession?.isLoading == true

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: ChromeMetrics.smallIconSize, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search or enter website name", text: $browserModel.addressText)
                .textFieldStyle(.plain)
                .font(.system(size: ChromeMetrics.bodyFontSize))
                .foregroundStyle(.primary)
                .focused($focused)
                .onSubmit { onSubmit() }
                .onChange(of: focused) { _, isFocused in
                    if isFocused {
                        selectTextForCurrentFocusIfNeeded()
                    } else {
                        didSelectTextForCurrentFocus = false
                    }
                }
                .onTapGesture {
                    selectTextForCurrentFocusIfNeeded()
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
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.9))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(focused ? 0.9 : 0), lineWidth: 2)
        }
    }

    private func selectTextForCurrentFocusIfNeeded() {
        guard didSelectTextForCurrentFocus == false else {
            return
        }

        didSelectTextForCurrentFocus = true
        DispatchQueue.main.async {
            AddressFieldTextSelector.selectCurrentFieldEditorContents()
        }
    }
}

private enum AddressFieldTextSelector {
    @MainActor
    static func selectCurrentFieldEditorContents() {
        guard let window = NSApp.keyWindow else {
            return
        }

        if let editor = window.firstResponder as? NSTextView {
            editor.selectAll(nil)
            return
        }

        window.fieldEditor(false, for: nil)?.selectAll(nil)
    }
}

// MARK: - Tabs

/// Separate-layout tab strip. Each tab shrinks to a favicon dot when `asDots`.
private struct TabStrip: View {
    @Environment(BrowserModel.self) private var browserModel
    let onPickDot: () -> Void

    var body: some View {
        @Bindable var browserModel = browserModel

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(browserModel.tabs) { tab in
                    TabButton(
                        tab: tab,
                        isSelected: tab.id == browserModel.selectedTabID,
                        onSelect: {
                            browserModel.selectedTabID = tab.id
                            onPickDot()
                        }
                    )
                    .frame(width: tab.isPinned ? 44 : 220)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: ChromeMetrics.tabBarHeight)
    }
}

/// Compact-layout inline tabs, sitting next to the navigation controls.
private struct InlineTabStrip: View {
    @Environment(BrowserModel.self) private var browserModel
    let onPickDot: () -> Void

    var body: some View {
        @Bindable var browserModel = browserModel

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(browserModel.tabs) { tab in
                    TabButton(
                        tab: tab,
                        isSelected: tab.id == browserModel.selectedTabID,
                        onSelect: {
                            browserModel.selectedTabID = tab.id
                            onPickDot()
                        }
                    )
                    .frame(width: tab.isPinned ? 40 : 150)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: 460)
        .frame(height: ChromeMetrics.controlHeight)
    }
}

private struct TabButton: View {
    let tab: BrowserTab
    let isSelected: Bool
    var minimized: Bool = false
    let onSelect: () -> Void

    @State private var isHovering = false

    // One stable view. Minimizing shrinks the tab *vertically* into a thin bar:
    // the height collapses, the title/close fade out, and the favicon shrinks —
    // width and the favicon's position stay put, so it reads as a minimized tab
    // (not gone) and the transition is a smooth resize, not a view swap.
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    TabFavicon(tab: tab, size: minimized ? 10 : 14)

                    if tab.isPinned == false {
                        Text(tab.displayTitle)
                            .font(.system(size: ChromeMetrics.bodyFontSize, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(minimized ? 0 : 1)
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
                    .opacity(minimized ? 0 : 1)
            }
        }
        .frame(height: minimized ? ChromeMetrics.minimizedTabHeight : ChromeMetrics.tabHeight)
        .background {
            tabBackground
        }
        .clipped()
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
        } else if minimized {
            Capsule(style: .continuous)
                .fill(.quaternary)
        } else if isHovering {
            Capsule(style: .continuous)
                .fill(.quaternary)
        }
    }
}

private struct TabFavicon: View {
    let tab: BrowserTab
    var size: CGFloat = 15

    var body: some View {
        FaviconIcon(
            faviconURLString: tab.faviconURLString,
            fallbackSystemName: tab.urlString == nil ? "plus" : "globe",
            size: size
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
