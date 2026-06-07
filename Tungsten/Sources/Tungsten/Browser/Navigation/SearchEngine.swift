import Foundation

private enum BrowserQueryEncoding {
    static func encode(_ query: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+"))
        return query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
    }
}

enum SearchEngine: String, CaseIterable, Codable, Identifiable {
    case duckDuckGo
    case google
    case bing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .google:     return "Google"
        case .bing:       return "Bing"
        }
    }

    var homepageURL: String {
        switch self {
        case .duckDuckGo: return "https://duck.ai/"
        case .google:     return "https://www.google.com"
        case .bing:       return "https://www.bing.com"
        }
    }

    func searchURL(for query: String) -> String {
        let encoded = BrowserQueryEncoding.encode(query)

        switch self {
        case .duckDuckGo:
            return "https://duckduckgo.com/?q=\(encoded)"
        case .google:
            return "https://www.google.com/search?q=\(encoded)"
        case .bing:
            return "https://www.bing.com/search?q=\(encoded)"
        }
    }
}

enum AddressBarAIProvider: String, CaseIterable, Codable, Identifiable {
    case duckDuckGoAI
    case googleAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .duckDuckGoAI:
            return "DuckDuckGo AI"
        case .googleAI:
            return "Google AI"
        }
    }

    func responseURL(for question: String) -> String {
        let encoded = BrowserQueryEncoding.encode(question)

        switch self {
        case .duckDuckGoAI:
            return "https://duck.ai/chat?prompt=1&home=1&q=\(encoded)"
        case .googleAI:
            return "https://www.google.com/search?udm=50&q=\(encoded)"
        }
    }
}
