import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    let shortcutManager: ShortcutManager

    @State private var recordingActionID: ShortcutActionID?
    @State private var conflictMessage: String?
    @State private var refreshToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcuts")
                    .font(.title2.weight(.semibold))
                Text("Remap supported browser shortcuts.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(ShortcutCategory.allCases, id: \.self) { category in
                        ShortcutCategorySection(
                            category: category,
                            shortcutManager: shortcutManager,
                            recordingActionID: $recordingActionID,
                            conflictMessage: $conflictMessage,
                            refreshToken: $refreshToken
                        )
                    }
                }
                .padding(24)
            }

            if let conflictMessage {
                Divider()
                Text(conflictMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        }
        .frame(width: 760, height: 560)
        .onChange(of: recordingActionID) { _, newValue in
            ShortcutRecordingState.shared.isRecording = newValue != nil
        }
        .onDisappear {
            ShortcutRecordingState.shared.isRecording = false
        }
    }
}

private struct ShortcutCategorySection: View {
    let category: ShortcutCategory
    let shortcutManager: ShortcutManager

    @Binding var recordingActionID: ShortcutActionID?
    @Binding var conflictMessage: String?
    @Binding var refreshToken: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.rawValue)
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(shortcutManager.actions(in: category)) { action in
                    ShortcutRow(
                        action: action,
                        shortcutManager: shortcutManager,
                        recordingActionID: $recordingActionID,
                        conflictMessage: $conflictMessage,
                        refreshToken: $refreshToken
                    )

                    if action.id != shortcutManager.actions(in: category).last?.id {
                        Divider()
                    }
                }
            }
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    let shortcutManager: ShortcutManager

    @Binding var recordingActionID: ShortcutActionID?
    @Binding var conflictMessage: String?
    @Binding var refreshToken: Int

    var body: some View {
        let isRecording = recordingActionID == action.id

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .foregroundStyle(action.isAvailable ? .primary : .secondary)
            }

            Spacer(minLength: 12)

            Text(isRecording ? "Press shortcut" : shortcutManager.displayString(for: action.id))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(action.isAvailable ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.background.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(minWidth: 170, alignment: .trailing)

            if action.isAvailable {
                Button(isRecording ? "Cancel" : "Record") {
                    if isRecording {
                        recordingActionID = nil
                    } else {
                        conflictMessage = nil
                        recordingActionID = action.id
                    }
                }

                Button("Reset") {
                    shortcutManager.resetBinding(for: action.id)
                    conflictMessage = nil
                    refreshToken += 1
                }

                Button("Clear") {
                    shortcutManager.clearBinding(for: action.id)
                    conflictMessage = nil
                    refreshToken += 1
                }
            } else {
                Text("Coming soon")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            ShortcutCaptureView(isActive: isRecording) { binding in
                handleCapture(binding)
            }
            .frame(width: 0, height: 0)
        }
    }

    private func handleCapture(_ binding: ShortcutBinding?) {
        guard recordingActionID == action.id else {
            return
        }

        guard let binding else {
            recordingActionID = nil
            return
        }

        switch shortcutManager.setCustomBinding(binding, for: action.id) {
        case .assigned:
            conflictMessage = nil
            recordingActionID = nil
            refreshToken += 1
        case .invalid:
            conflictMessage = "Use Command, Option, or Control with a key."
        case .unavailable:
            conflictMessage = "\(action.title) is coming soon."
            recordingActionID = nil
        case .conflict(let existingActionID):
            let title = shortcutManager.action(id: existingActionID)?.title ?? "another action"
            conflictMessage = "\(binding.displayString) is already assigned to \(title)."
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (ShortcutBinding?) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onCapture = onCapture

        if isActive {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class ShortcutCaptureNSView: NSView {
    var onCapture: ((ShortcutBinding?) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCapture?(nil)
            return
        }

        onCapture?(ShortcutBinding(event: event))
    }
}
