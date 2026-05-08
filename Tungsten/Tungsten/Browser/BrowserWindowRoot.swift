import AppKit
import SwiftUI

struct BrowserWindowRoot: View {
    @Environment(\.openWindow) private var openWindow

    private let kind: BrowserWindowKind
    private let shortcutManager: ShortcutManager
    private let historyStore: HistoryStore
    private let appPreferences: AppPreferences
    private let windowSessionCoordinator: BrowserWindowSessionCoordinator
    @State private var browserModel: BrowserModel?
    @State private var threadStore: BrowserThreadStore?

    init(
        kind: BrowserWindowKind,
        shortcutManager: ShortcutManager,
        historyStore: HistoryStore,
        appPreferences: AppPreferences,
        windowSessionCoordinator: BrowserWindowSessionCoordinator
    ) {
        self.kind = kind
        self.shortcutManager = shortcutManager
        self.historyStore = historyStore
        self.appPreferences = appPreferences
        self.windowSessionCoordinator = windowSessionCoordinator
    }

    var body: some View {
        Group {
            if let browserModel {
                BrowserSplitView()
                    .environment(browserModel)
                    .environment(appPreferences)
                    .background(
                        ShortcutEventMonitor(
                            shortcutManager: shortcutManager,
                            commandContext: BrowserCommandContext(
                                browserModel: browserModel,
                                openNormalWindow: { openWindow(id: BrowserWindowKind.normal.sceneID) },
                                openIncognitoWindow: { openWindow(id: BrowserWindowKind.incognito.sceneID) }
                            )
                        )
                    )
                    .background(
                        WindowCloseObserver { finishClose in
                            browserModel.closeBrowsersForWindowClose {
                                releaseThreadStoreIfNeeded()
                                finishClose()
                            }
                        }
                    )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        initializeBrowserModelIfNeeded()
                    }
            }
        }
        .frame(minWidth: 1280, minHeight: 720)
        .navigationTitle(kind.title)
    }

    private func initializeBrowserModelIfNeeded() {
        guard browserModel == nil else {
            return
        }

        let threadStore = windowSessionCoordinator.makeThreadStore(kind: kind)
        self.threadStore = threadStore

        browserModel = BrowserModel(
            kind: kind,
            historyStore: historyStore,
            appPreferences: appPreferences,
            threadStore: threadStore
        )
    }

    private func releaseThreadStoreIfNeeded() {
        guard let threadStore else {
            return
        }

        windowSessionCoordinator.releaseThreadStore(threadStore, kind: kind)
        self.threadStore = nil
    }
}

private struct WindowCloseObserver: NSViewRepresentable {
    let onWindowShouldClose: (@escaping () -> Void) -> Void

    func makeCoordinator() -> WindowCloseObserverBox {
        WindowCloseObserverBox()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onWindowShouldClose = onWindowShouldClose

        DispatchQueue.main.async {
            context.coordinator.install(window: nsView.window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: WindowCloseObserverBox) {
        coordinator.remove()
    }
}

@MainActor
private final class WindowCloseObserverBox: NSObject, NSWindowDelegate {
    var onWindowShouldClose: ((@escaping () -> Void) -> Void)?

    private weak var window: NSWindow?
    private weak var previousDelegate: (any NSWindowDelegate)?
    private var isWaitingForBrowserClose = false

    func install(window: NSWindow?) {
        guard let window else {
            return
        }

        guard self.window !== window else {
            return
        }

        remove()
        self.window = window
        previousDelegate = window.delegate
        window.delegate = self
    }

    func remove() {
        if let window {
            if (window.delegate as AnyObject?) === self {
                window.delegate = previousDelegate
            }
        }

        window = nil
        previousDelegate = nil
        isWaitingForBrowserClose = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isWaitingForBrowserClose {
            return false
        }

        if previousDelegate?.windowShouldClose?(sender) == false {
            return false
        }

        guard let onWindowShouldClose else {
            return true
        }

        isWaitingForBrowserClose = true
        onWindowShouldClose { [weak self, weak sender] in
            guard let self, let sender else {
                return
            }

            self.remove()
            sender.close()
        }

        return false
    }

    deinit {
        MainActor.assumeIsolated {
            remove()
        }
    }
}
