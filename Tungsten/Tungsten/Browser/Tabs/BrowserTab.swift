import Foundation

struct BrowserTab: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var urlString: String?
    var title: String?
    var faviconURLString: String?
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        urlString: String? = nil,
        title: String? = nil,
        faviconURLString: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.urlString = urlString
        self.title = title
        self.faviconURLString = faviconURLString
        self.isPinned = isPinned
    }

    var displayTitle: String {
        if let title {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle.isEmpty == false {
                return trimmedTitle
            }
        }

        if let urlString,
           let host = URLComponents(string: urlString)?.host,
           host.isEmpty == false {
            return host
        }

        return "Untitled"
    }

    var displaySubtitle: String {
        guard let urlString, urlString.isEmpty == false else {
            return "New Tab"
        }

        return urlString
    }

    var sanitizedForPersistence: BrowserTab {
        var tab = self
        tab.urlString = tab.urlString.map(Self.cappedText)
        tab.title = tab.title.map(Self.cappedText)
        tab.faviconURLString = tab.faviconURLString.map(Self.cappedText)
        return tab
    }

    mutating func update(
        urlString: String? = nil,
        title: String? = nil,
        faviconURLString: String? = nil,
        updatedAt: Date = Date()
    ) {
        if let urlString {
            self.urlString = urlString
        }

        if let title {
            self.title = title
        }

        if let faviconURLString {
            self.faviconURLString = faviconURLString
        }

        self.updatedAt = updatedAt
    }

    private static func cappedText(_ value: String) -> String {
        let maxPersistedCharacters = 4_000
        guard value.count > maxPersistedCharacters else {
            return value
        }

        return String(value.prefix(maxPersistedCharacters))
    }
}
