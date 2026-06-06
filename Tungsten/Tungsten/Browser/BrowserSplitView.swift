/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Safari-style browser shell: composes the Liquid Glass chrome over the page,
plus the find bar and history sheet.
*/

import AppKit
import SwiftUI

struct BrowserSplitView: View {
    @Environment(BrowserModel.self) private var browserModel
    @Environment(AppPreferences.self) private var appPreferences

    var body: some View {
        @Bindable var browserModel = browserModel
        let chromeHeight = ChromeMetrics.totalHeight(for: appPreferences.tabLayout)

        ZStack(alignment: .top) {
            if let pageSession = browserModel.activePageSession {
                BrowserDetailView(pageSession: pageSession, topInset: chromeHeight)
            } else {
                StartPageView(
                    isPrivate: browserModel.kind.isIncognito,
                    historyStore: browserModel.historyStore,
                    topInset: chromeHeight,
                    onOpen: { browserModel.openURLString($0) }
                )
            }

            if browserModel.isFindBarVisible {
                VStack {
                    HStack {
                        Spacer()

                        FindBar(
                            text: $browserModel.findText,
                            focusRequestID: browserModel.findFocusRequestID,
                            onTextChange: { browserModel.updateFindText($0) },
                            onPrevious: { browserModel.findPreviousInPage() },
                            onNext: { browserModel.findNextInPage() },
                            onClose: { browserModel.closeFindInPage() }
                        )
                        .padding(.trailing, 16)
                    }
                    .padding(.top, chromeHeight + 8)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            BrowserChrome(tabLayout: appPreferences.tabLayout)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .animation(.smooth(duration: 0.16), value: browserModel.isFindBarVisible)
        .containerBackground(.clear, for: .window)
        .background(SafariWindowChromeConfigurator(transparencyEnabled: appPreferences.transparencyEnabled))
        .toolbar(removing: .title)
        .sheet(isPresented: $browserModel.isHistoryVisible) {
            HistoryView(historyStore: browserModel.historyStore) { entry in
                browserModel.openHistoryEntry(entry)
            }
            .frame(minWidth: 640, minHeight: 520)
        }
    }
}

// MARK: - Window configuration

private struct SafariWindowChromeConfigurator: NSViewRepresentable {
    let transparencyEnabled: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true

        // Liquid Glass is meant to float over content and adapt. Honor the
        // user's "Translucent window" preference, but always fall back to a
        // solid adaptive backing when the system asks to reduce transparency.
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let translucent = transparencyEnabled && reduceTransparency == false

        window.isOpaque = false
        window.backgroundColor = translucent ? .clear : AppPreferences.opaqueWindowBackgroundColor
    }
}

// MARK: - Find bar

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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
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

#Preview {
    @Previewable @State var model = BrowserModel()
    @Previewable @State var preferences = AppPreferences()

    BrowserSplitView()
        .environment(model)
        .environment(preferences)
}
