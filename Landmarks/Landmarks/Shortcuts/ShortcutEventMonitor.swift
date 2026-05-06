import AppKit
import SwiftUI

struct ShortcutEventMonitor: NSViewRepresentable {
    let shortcutManager: ShortcutManager
    let browserModel: BrowserModel

    func makeCoordinator() -> ShortcutEventMonitorBox {
        ShortcutEventMonitorBox()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.install(
                window: nsView.window,
                shortcutManager: shortcutManager,
                browserModel: browserModel
            )
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ShortcutEventMonitorBox) {
        coordinator.remove()
    }
}

@MainActor
final class ShortcutRecordingState {
    static let shared = ShortcutRecordingState()

    var isRecording = false
}

@MainActor
final class ShortcutEventMonitorBox {
    private weak var window: NSWindow?
    private var monitor: Any?

    func install(window: NSWindow?, shortcutManager: ShortcutManager, browserModel: BrowserModel) {
        self.window = window

        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            guard event.window === self.window else {
                return event
            }
            guard ShortcutRecordingState.shared.isRecording == false else {
                return event
            }
            guard
                let binding = ShortcutBinding(event: event),
                let action = shortcutManager.dispatchableAction(for: binding),
                ShortcutDispatcher.dispatch(action, browserModel: browserModel)
            else {
                return event
            }

            return nil
        }
    }

    func remove() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
