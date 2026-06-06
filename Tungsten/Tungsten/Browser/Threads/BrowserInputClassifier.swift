import Foundation

enum BrowserInputSubmission: Equatable {
    case page(urlString: String)
    case question(String)
}

enum BrowserInputClassifier {
    static func submission(for input: String, searchEngine: SearchEngine) -> BrowserInputSubmission? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        if let searchQuery = forcedSearchQuery(from: trimmed) {
            return .page(urlString: searchEngine.searchURL(for: searchQuery))
        }

        if let target = AddressResolver.directNavigationTarget(for: trimmed) {
            return .page(urlString: target)
        }

        return .page(urlString: searchEngine.searchURL(for: trimmed))
    }

    static func fallbackSearchURL(for question: String, searchEngine: SearchEngine) -> String {
        searchEngine.searchURL(for: question)
    }

    private static func forcedSearchQuery(from input: String) -> String? {
        let keyword = "search"
        let lowercased = input.lowercased()
        guard lowercased.hasPrefix(keyword) else {
            return nil
        }

        let suffix = input.dropFirst(keyword.count)
        guard let firstCharacter = suffix.first else {
            return nil
        }

        let query: Substring
        if firstCharacter == ":" {
            query = suffix.dropFirst()
        } else if firstCharacter.isWhitespace {
            query = suffix
        } else {
            return nil
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuery.isEmpty ? nil : trimmedQuery
    }
}
