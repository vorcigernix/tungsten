import SwiftUI

struct HistoryView: View {
    @Bindable var historyStore: HistoryStore
    let openEntry: (HistoryEntry) -> Void

    @State private var searchText = ""
    @State private var isClearConfirmationPresented = false

    private var filteredEntries: [HistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return historyStore.entries
        }

        return historyStore.entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(query)
                || entry.urlString.localizedCaseInsensitiveContains(query)
                || host(for: entry).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredEntries.isEmpty {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath")
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                } else {
                    List(filteredEntries) { entry in
                        HistoryEntryRow(entry: entry, host: host(for: entry)) {
                            openEntry(entry)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear History", systemImage: "trash") {
                        isClearConfirmationPresented = true
                    }
                    .disabled(historyStore.entries.isEmpty)
                }
            }
            .confirmationDialog(
                "Clear all browsing history?",
                isPresented: $isClearConfirmationPresented
            ) {
                Button("Clear History", role: .destructive) {
                    historyStore.clear()
                }
                Button("Cancel", role: .cancel) {
                }
            }
        }
    }

    private func host(for entry: HistoryEntry) -> String {
        URLComponents(string: entry.urlString)?.host ?? entry.urlString
    }
}

private struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let host: String
    let openEntry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(entry.urlString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Text(entry.visitedAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button("Open", systemImage: "arrow.up.forward.square") {
                openEntry()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Open")
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    @Previewable @State var historyStore: HistoryStore = {
        let store = HistoryStore()
        store.recordVisit(urlString: "https://example.com", title: "Example", visitedAt: Date())
        return store
    }()

    HistoryView(historyStore: historyStore) { _ in }
}
