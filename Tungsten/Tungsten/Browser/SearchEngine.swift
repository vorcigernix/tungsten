import Foundation

enum SearchEngine: String, CaseIterable, Codable, Identifiable {
    case googleAIMode
    case perplexity
    case duckAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleAIMode: return "Google AI Mode"
        case .perplexity:   return "Perplexity"
        case .duckAI:       return "Duck.ai"
        }
    }

    var homepageURL: String {
        switch self {
        case .googleAIMode: return "https://www.google.com/?udm=50"
        case .perplexity:   return "https://www.perplexity.ai"
        case .duckAI:       return "https://duck.ai"
        }
    }

    func searchURL(for query: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query

        switch self {
        case .googleAIMode:
            return "https://www.google.com/search?q=\(encoded)&udm=50"
        case .perplexity:
            return "https://www.perplexity.ai/search?q=\(encoded)"
        case .duckAI:
            return "https://duck.ai/?q=\(encoded)"
        }
    }
}
