import Foundation

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
        case .duckDuckGo: return "https://duckduckgo.com"
        case .google:     return "https://www.google.com"
        case .bing:       return "https://www.bing.com"
        }
    }

    func searchURL(for query: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query

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
