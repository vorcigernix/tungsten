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
    @Environment(AppPreferences.self) private var appPreferences
    // The transparent window + window-level visual-effect material force the
    // whole window into alpha-blended compositing before CEF can present its
    // first frame, which made cold launch feel laggy. Hold those off for a
    // short beat so the opaque content paints first, then enable the frosting.
    @State private var compositingEnabled = false

    var body: some View {
        @Bindable var browserModel = browserModel
        let pageSession = browserModel.activePageSession
        let sidebarVisibility = Binding<NavigationSplitViewVisibility> {
            browserModel.isSidebarVisible ? .all : .detailOnly
        } set: { visibility in
            browserModel.isSidebarVisible = visibility != .detailOnly
        }

        NavigationSplitView(columnVisibility: sidebarVisibility) {
            BrowserSidebar()
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 560)
        } detail: {
            if let pageSession {
                ZStack(alignment: .topTrailing) {
                    BrowserDetailView(pageSession: pageSession)

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
                ContentUnavailableView("No Page", systemImage: "text.bubble")
            }
        }
        // Frosty glass fills the window-level gutters around the rounded
        // sidebar panel and around the inset page. NSVisualEffectView
        // (which Material uses under the hood) needs framebuffer content
        // behind the window to blur, so WindowTransparencyEnabler keeps the
        // host NSWindow non-opaque — otherwise the material would just blur
        // the window's own backing color and look flat.
        //
        // When the user disables transparency we paint a solid warm color
        // behind everything and skip the window-transparency dance entirely.
        .containerBackground(windowContainerStyle, for: .window)
        .background(WindowTransparencyEnabler(enabled: appPreferences.transparencyEnabled && compositingEnabled))
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            compositingEnabled = true
        }
        .sheet(isPresented: $browserModel.isHistoryVisible) {
            HistoryView(historyStore: browserModel.historyStore) { entry in
                browserModel.openHistoryEntry(entry)
            }
            .frame(minWidth: 640, minHeight: 520)
        }
    }

    private var windowContainerStyle: AnyShapeStyle {
        guard appPreferences.transparencyEnabled else {
            return AnyShapeStyle(Color(nsColor: AppPreferences.opaqueWindowBackgroundColor))
        }

        return compositingEnabled
            ? AnyShapeStyle(.regularMaterial)
            : AnyShapeStyle(.windowBackground)
    }
}

/// Marks the host NSWindow as transparent so SwiftUI's `.containerBackground(.clear, …)`
/// actually shows through to the desktop. The CEF NSView in the detail column
/// stays opaque (it draws the page), so only areas SwiftUI leaves clear become
/// transparent — i.e. the strip around the sidebar's rounded glass panel.
private struct WindowTransparencyEnabler: NSViewRepresentable {
    let enabled: Bool

    final class Coordinator {
        weak var window: NSWindow?
        var transparent = false
        var animationsDisabled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let shouldBeTransparent = enabled
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            coordinator.window = window

            // Disable AppKit's window transform animations (close / zoom /
            // miniaturize / order). On macOS 26 + non-opaque windows + CEF,
            // those animations have torn-down captured references and crash
            // inside `-[_NSWindowTransformAnimation dealloc]` during
            // `CA::Transaction::commit`. Skipping the animations sidesteps
            // the entire class of bug; new browser windows just appear, which
            // matches what most browsers do anyway.
            if coordinator.animationsDisabled == false {
                coordinator.animationsDisabled = true
                window.animationBehavior = .none
            }

            guard coordinator.transparent != shouldBeTransparent else { return }
            coordinator.transparent = shouldBeTransparent

            if shouldBeTransparent {
                window.isOpaque = false
                window.backgroundColor = .clear
            } else {
                window.isOpaque = true
                window.backgroundColor = .windowBackgroundColor
            }
            window.invalidateShadow()
        }
    }
}

private struct BrowserSidebar: View {
    @Environment(BrowserModel.self) private var browserModel

    var body: some View {
        @Bindable var browserModel = browserModel

        VStack(spacing: 0) {
            ThreadHeader(
                threads: browserModel.threads,
                selectedThreadID: $browserModel.selectedThreadID,
                onNewThread: { browserModel.createThread() },
                onCloseThread: { browserModel.closeSelectedThread() }
            )

            Divider()

            ThreadTimeline(
                thread: browserModel.selectedThread,
                activePageTurnID: browserModel.selectedThread?.activePageTurnID,
                isGeneratingResponse: browserModel.isGeneratingResponse,
                onActivatePage: { browserModel.activatePageTurnInSelectedThread($0) }
            )

            Divider()

            ChatInput(
                text: $browserModel.addressText,
                focusRequestID: browserModel.addressFocusRequestID,
                onSubmit: { browserModel.submitAddressBar() }
            )
        }
    }
}

private struct ThreadHeader: View {
    @Environment(BrowserModel.self) private var browserModel

    let threads: [BrowserThread]
    @Binding var selectedThreadID: BrowserThread.ID?
    let onNewThread: () -> Void
    let onCloseThread: () -> Void

    private var selectedThread: BrowserThread? {
        guard let selectedThreadID else {
            return nil
        }

        return threads.first { $0.id == selectedThreadID }
    }

    var body: some View {
        let pageSession = browserModel.activePageSession

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Thread", selection: $selectedThreadID) {
                    ForEach(threads) { thread in
                        Label {
                            Text(thread.displayTitle)
                        } icon: {
                            Image(systemName: thread.isPinned ? "pin.circle" : "text.bubble")
                        }
                        .tag(Optional(thread.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Menu {
                    Button(selectedThread?.isPinned == true ? "Unpin Thread" : "Pin Thread", systemImage: selectedThread?.isPinned == true ? "pin.slash" : "pin") {
                        if let selectedThread {
                            browserModel.toggleThreadPin(selectedThread)
                        }
                    }
                    .disabled(selectedThread == nil)

                    Button("Clear Unpinned Threads", systemImage: "xmark.circle") {
                        browserModel.clearUnpinnedThreads()
                    }
                    .disabled(threads.allSatisfy(\.isPinned))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Thread Actions")

                Button("New Thread", systemImage: "plus") {
                    onNewThread()
                }
                .labelStyle(.iconOnly)
                .help("New Thread")

                Button("Close Thread", systemImage: "xmark") {
                    onCloseThread()
                }
                .labelStyle(.iconOnly)
                .disabled(threads.isEmpty)
                .help("Close Thread")
            }

            HStack(spacing: 8) {
                Button("Back", systemImage: "chevron.backward") {
                    pageSession?.goBack()
                }
                .labelStyle(.iconOnly)
                .disabled(pageSession?.canGoBack != true)
                .help("Back")

                Button("Forward", systemImage: "chevron.forward") {
                    pageSession?.goForward()
                }
                .labelStyle(.iconOnly)
                .disabled(pageSession?.canGoForward != true)
                .help("Forward")

                if pageSession?.isLoading == true {
                    Button("Stop", systemImage: "xmark") {
                        pageSession?.stopLoading()
                    }
                    .labelStyle(.iconOnly)
                    .help("Stop")
                } else {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        pageSession?.reload()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(pageSession == nil)
                    .help("Reload")
                }

                Spacer(minLength: 8)

                if browserModel.kind.isIncognito {
                    Label("Private", systemImage: "shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.iconOnly)
                        .help("Private Window")
                }
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct ThreadTimeline: View {
    let thread: BrowserThread?
    let activePageTurnID: BrowserTurn.ID?
    let isGeneratingResponse: Bool
    let onActivatePage: (BrowserTurn.ID) -> Void

    private var turns: [BrowserTurn] {
        thread?.turns ?? []
    }

    private var scrollTarget: AnyHashable? {
        if isGeneratingResponse {
            return AnyHashable("pending-assistant")
        }

        return turns.last.map { AnyHashable($0.id) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(turns) { turn in
                        ThreadTurnBubble(
                            turn: turn,
                            isActivePage: turn.kind == .page && turn.id == activePageTurnID,
                            onActivatePage: onActivatePage
                        )
                        .id(turn.id)
                    }

                    if isGeneratingResponse {
                        PendingAssistantBubble()
                            .id("pending-assistant")
                    }
                }
                .padding(12)
            }
            .onChange(of: turns.count) { _, _ in
                scrollToLatest(with: proxy)
            }
            .onChange(of: isGeneratingResponse) { _, _ in
                scrollToLatest(with: proxy)
            }
            .onAppear {
                scrollToLatest(with: proxy, animated: false)
            }
        }
    }

    private func scrollToLatest(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let scrollTarget else {
            return
        }

        let action = {
            proxy.scrollTo(scrollTarget, anchor: .bottom)
        }

        if animated {
            withAnimation(.smooth(duration: 0.24)) {
                action()
            }
        } else {
            action()
        }
    }
}

private struct ThreadTurnBubble: View {
    let turn: BrowserTurn
    let isActivePage: Bool
    let onActivatePage: (BrowserTurn.ID) -> Void

    var body: some View {
        switch turn.kind {
        case .page:
            pageRow
        case .userQuestion:
            alignedTextBubble(isUserQuestion: true, fill: Color.accentColor.opacity(0.16))
        case .assistantResponse, .system:
            alignedTextBubble(isUserQuestion: false, fill: Color(nsColor: .controlBackgroundColor).opacity(0.92))
        }
    }

    private var pageRow: some View {
        Button {
            onActivatePage(turn.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "globe")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(turn.displayTitle)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(turn.urlString ?? turn.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isActivePage ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.15),
                        lineWidth: isActivePage ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func alignedTextBubble(isUserQuestion: Bool, fill: Color) -> some View {
        HStack {
            if isUserQuestion {
                Spacer(minLength: 36)
            }

            Text(turn.displayTitle)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
                }
                .frame(maxWidth: 280, alignment: isUserQuestion ? .trailing : .leading)

            if isUserQuestion == false {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUserQuestion ? .trailing : .leading)
    }
}

private struct PendingAssistantBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rainbowRotation = 0.0

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Thinking")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            .red.opacity(0.5),
                            .orange.opacity(0.5),
                            .yellow.opacity(0.45),
                            .green.opacity(0.5),
                            .cyan.opacity(0.5),
                            .blue.opacity(0.5),
                            .purple.opacity(0.5),
                            .red.opacity(0.5)
                        ],
                        center: .center
                    ),
                    lineWidth: 1.25
                )
                .rotationEffect(.degrees(rainbowRotation))
        }
        .onAppear {
            guard reduceMotion == false else {
                rainbowRotation = 0
                return
            }

            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                rainbowRotation = 360
            }
        }
        .onChange(of: reduceMotion) { _, newValue in
            if newValue {
                rainbowRotation = 0
            } else {
                withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                    rainbowRotation = 360
                }
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
