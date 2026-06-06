import AppKit
import SwiftUI

struct BrowserWindowRoot: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(TungstenAppModel.self) private var appModel

    private let kind: BrowserWindowKind
    @State private var windowModel: BrowserWindowModel?

    init(kind: BrowserWindowKind) {
        self.kind = kind
    }

    var body: some View {
        Group {
            if let windowModel {
                let browserModel = windowModel.browserModel

                BrowserSplitView()
                    .environment(browserModel)
                    .environment(appModel.appPreferences)
                    .background(
                        ShortcutEventMonitor(
                            shortcutManager: appModel.shortcutManager,
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
                                windowModel.releaseTabStoreIfNeeded()
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
        guard windowModel == nil else {
            return
        }

        windowModel = appModel.makeBrowserWindowModel(kind: kind)
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
