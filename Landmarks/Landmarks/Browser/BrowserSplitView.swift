/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The browser shell. Standard macOS NavigationSplitView with a leading
sidebar that holds the tab list and the chat-style input, and a detail
column that hosts the active browser surface.
*/

import SwiftUI

struct BrowserSplitView: View {
    @Environment(BrowserModel.self) private var browserModel

    var body: some View {
        let tab = browserModel.selectedTab

        NavigationSplitView {
            BrowserSidebar()
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 560)
        } detail: {
            if let tab {
                BrowserDetailView(tab: tab)
            } else {
                ContentUnavailableView("No Tabs", systemImage: "rectangle.dashed")
            }
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

private struct ChatInput: View {
    @Binding var text: String
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
