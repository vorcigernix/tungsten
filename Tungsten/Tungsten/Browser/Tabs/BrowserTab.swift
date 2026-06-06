import Foundation

enum BrowserTabPrivacyMode: String, Codable, CaseIterable, Equatable {
    case normal
    case incognito
    case tor

    var isEphemeral: Bool {
        self != .normal
    }

    var usesTorProxy: Bool {
        self == .tor
    }
}

struct BrowserTab: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var urlString: String?
    var title: String?
    var faviconURLString: String?
    var isPinned: Bool
    var privacyMode: BrowserTabPrivacyMode

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case urlString
        case title
        case faviconURLString
        case isPinned
        case privacyMode
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        urlString: String? = nil,
        title: String? = nil,
        faviconURLString: String? = nil,
        isPinned: Bool = false,
        privacyMode: BrowserTabPrivacyMode = .normal
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.urlString = urlString
        self.title = title
        self.faviconURLString = faviconURLString
        self.isPinned = isPinned
        self.privacyMode = privacyMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        faviconURLString = try container.decodeIfPresent(String.self, forKey: .faviconURLString)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        privacyMode = try container.decodeIfPresent(BrowserTabPrivacyMode.self, forKey: .privacyMode) ?? .normal
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(urlString, forKey: .urlString)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(faviconURLString, forKey: .faviconURLString)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(privacyMode, forKey: .privacyMode)
    }

    var isEphemeral: Bool {
        privacyMode.isEphemeral
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
