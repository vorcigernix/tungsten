/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The browser shell. Standard macOS NavigationSplitView with a leading
sidebar that holds the tab list and the chat-style input, and a detail
column that hosts the active browser surface.
*/

import AppKit
import SwiftUI

struct BrowserSplitView: View {
    @Environment(BrowserModel.self) private var browserModel

    var body: some View {
        @Bindable var browserModel = browserModel
        let tab = browserModel.selectedTab
        let sidebarVisibility = Binding<NavigationSplitViewVisibility> {
            browserModel.isSidebarVisible ? .all : .detailOnly
        } set: { visibility in
            browserModel.isSidebarVisible = visibility != .detailOnly
        }

        NavigationSplitView(columnVisibility: sidebarVisibility) {
            BrowserSidebar()
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 560)
        } detail: {
            if let tab {
                ZStack(alignment: .topTrailing) {
                    BrowserDetailView(tab: tab)

                    if browserModel.isFindBarVisible {
                        FindBar(
                            text: $browserModel.findText,
                            focusRequestID: browserModel.findFocusRequestID,
                            onTextChange: { browserModel.updateFindText($0) },
                            onPrevious: { browserModel.findPreviousInPage() },
                            onNext: { browserModel.findNextInPage() },
                            onClose: { browserModel.closeFindInPage() }
                        )
                        .padding(.top, 14)
                        .padding(.trailing, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.16), value: browserModel.isFindBarVisible)
            } else {
                ContentUnavailableView("No Tabs", systemImage: "rectangle.dashed")
            }
        }
        // Frosty glass fills the window-level gutters around the rounded
        // sidebar panel and around the inset page. NSVisualEffectView
        // (which Material uses under the hood) needs framebuffer content
        // behind the window to blur, so WindowTransparencyEnabler keeps the
        // host NSWindow non-opaque — otherwise the material would just blur
        // the window's own backing color and look flat.
        .containerBackground(.regularMaterial, for: .window)
        .background(WindowTransparencyEnabler())
    }
}

/// Marks the host NSWindow as transparent so SwiftUI's `.containerBackground(.clear, …)`
/// actually shows through to the desktop. The CEF NSView in the detail column
/// stays opaque (it draws the page), so only areas SwiftUI leaves clear become
/// transparent — i.e. the strip around the sidebar's rounded glass panel.
private struct WindowTransparencyEnabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.invalidateShadow()
        }
    }
}

private struct BrowserSidebar: View {
    @Environment(BrowserModel.self) private var browserModel

    var body: some View {
        @Bindable var browserModel = browserModel

        VStack(spacing: 0) {
            List(selection: $browserModel.selectedTabID) {
                SidebarControls(
                    tab: browserModel.selectedTab,
                    addTab: { browserModel.addTab() }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                ForEach(browserModel.tabs) { tab in
                    BrowserTabRow(tab: tab)
                        .tag(tab.id)
                        .contextMenu {
                            Button("Close Tab", systemImage: "xmark") {
                                browserModel.close(tab)
                            }
                        }
                }
            }
            .listStyle(.sidebar)

            Divider()

            ChatInput(
                text: $browserModel.addressText,
                focusRequestID: browserModel.addressFocusRequestID,
                onSubmit: { browserModel.submitAddressBar() }
            )
        }
    }
}

private struct SidebarControls: View {
    let tab: BrowserTab?
    let addTab: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Back", systemImage: "chevron.backward") {
                tab?.goBack()
            }
            .disabled(tab?.canGoBack != true)
            .help("Back")

            Button("Forward", systemImage: "chevron.forward") {
                tab?.goForward()
            }
            .disabled(tab?.canGoForward != true)
            .help("Forward")

            if tab?.isLoading == true {
                Button("Stop", systemImage: "xmark") {
                    tab?.stopLoading()
                }
                .help("Stop")
            } else {
                Button("Reload", systemImage: "arrow.clockwise") {
                    tab?.reload()
                }
                .disabled(tab == nil)
                .help("Reload")
            }

            Spacer(minLength: 8)

            Button("New Tab", systemImage: "plus") {
                addTab()
            }
            .help("New Tab")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.regular)
    }
}

private struct BrowserTabRow: View {
    let tab: BrowserTab

    var body: some View {
        Label {
            Text(tab.displayTitle)
                .lineLimit(1)
        } icon: {
            if tab.isLoading {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .symbolEffect(.rotate, isActive: true)
            } else if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "globe")
            }
        }
    }
}

private struct FindBar: View {
    @Binding var text: String
    let focusRequestID: Int
    let onTextChange: (String) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @FocusState private var isFocused: Bool

    private var hasQuery: Bool {
        text.isEmpty == false
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find", text: $text)
                .textFieldStyle(.plain)
                .frame(width: 190)
                .focused($isFocused)
                .onSubmit(onNext)

            Button("Previous", systemImage: "chevron.up") {
                onPrevious()
            }
            .disabled(hasQuery == false)
            .help("Previous")

            Button("Next", systemImage: "chevron.down") {
                onNext()
            }
            .disabled(hasQuery == false)
            .help("Next")

            Divider()
                .frame(height: 18)

            Button("Close", systemImage: "xmark") {
                onClose()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .onAppear {
            isFocused = true
        }
        .onChange(of: focusRequestID) { _, _ in
            isFocused = true
        }
        .onChange(of: text) { _, newValue in
            onTextChange(newValue)
        }
    }
}

private struct ChatInput: View {
    @Binding var text: String
    let focusRequestID: Int
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 58, maxHeight: 96)
                        .focused($isFocused)

                    if text.isEmpty {
                        Text("Ask anything or paste a URL")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(canSubmit ? Color.accentColor : Color.secondary.opacity(0.4))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(canSubmit == false)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.18),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            }
            .animation(.smooth(duration: 0.15), value: isFocused)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .onChange(of: focusRequestID) { _, _ in
            isFocused = true
        }
    }

    private func submit() {
        guard canSubmit else { return }
        onSubmit()
    }
}

#Preview {
    @Previewable @State var model = BrowserModel()

    BrowserSplitView()
        .environment(model)
}
