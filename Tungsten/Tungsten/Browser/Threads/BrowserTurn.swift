import Foundation

enum BrowserTurnKind: String, Codable, Equatable {
    case userQuestion
    case assistantResponse
    case page
    case system
}

struct BrowserTurn: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: BrowserTurnKind
    var text: String
    var urlString: String?
    var title: String?
    var faviconURLString: String?
    var createdAt: Date

    var displayTitle: String {
        switch kind {
        case .page:
            if let title, title.isEmpty == false {
                return title
            }

            if let urlString,
               let host = URL(string: urlString)?.host,
               host.isEmpty == false {
                return host
            }

            return urlString ?? text
        case .userQuestion, .assistantResponse, .system:
            return text
        }
    }

    static func question(_ text: String, id: UUID = UUID(), createdAt: Date = Date()) -> BrowserTurn {
        BrowserTurn(id: id, kind: .userQuestion, text: text, createdAt: createdAt)
    }

    static func assistant(_ text: String, id: UUID = UUID(), createdAt: Date = Date()) -> BrowserTurn {
        BrowserTurn(id: id, kind: .assistantResponse, text: text, createdAt: createdAt)
    }

    static func system(_ text: String, id: UUID = UUID(), createdAt: Date = Date()) -> BrowserTurn {
        BrowserTurn(id: id, kind: .system, text: text, createdAt: createdAt)
    }

    static func page(
        urlString: String,
        title: String? = nil,
        faviconURLString: String? = nil,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> BrowserTurn {
        BrowserTurn(
            id: id,
            kind: .page,
            text: title ?? urlString,
            urlString: urlString,
            title: title,
            faviconURLString: faviconURLString,
            createdAt: createdAt
        )
    }
}
