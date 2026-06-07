import Foundation

@Observable @MainActor
final class HistoryStore {
    private static let maxEntries = 1_000

    private let userDefaults: UserDefaults
    private let key: String

    private(set) var entries: [HistoryEntry] = []

    init(userDefaults: UserDefaults = .standard, key: String = "HistoryEntries") {
        self.userDefaults = userDefaults
        self.key = key
        load()
    }

    func recordVisit(urlString: String, title: String, visitedAt: Date = Date()) {
        guard let normalized = normalizedHTTPURLString(urlString) else {
            return
        }

        let storedTitle = displayTitle(for: normalized, title: title)

        if entries.first?.urlString == normalized {
            entries[0].title = storedTitle
            entries[0].visitedAt = visitedAt
        } else {
            entries.insert(
                HistoryEntry(urlString: normalized, title: storedTitle, visitedAt: visitedAt),
                at: 0
            )

            if entries.count > Self.maxEntries {
                entries.removeLast(entries.count - Self.maxEntries)
            }
        }

        persist()
    }

    func updateTitle(for urlString: String, title: String) {
        guard
            let normalized = normalizedHTTPURLString(urlString),
            let index = entries.firstIndex(where: { $0.urlString == normalized })
        else {
            return
        }

        let storedTitle = displayTitle(for: normalized, title: title)
        guard entries[index].title != storedTitle else {
            return
        }

        entries[index].title = storedTitle
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard let data = userDefaults.data(forKey: key) else {
            return
        }

        do {
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            userDefaults.set(data, forKey: key)
        } catch {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func normalizedHTTPURLString(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            trimmed.isEmpty == false,
            let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false,
            let url = components.url
        else {
            return nil
        }

        return url.absoluteString
    }

    private func displayTitle(for urlString: String, title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty == false {
            return trimmedTitle
        }

        return URLComponents(string: urlString)?.host ?? urlString
    }
}
