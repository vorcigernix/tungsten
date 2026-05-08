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

        if let target = AddressResolver.directNavigationTarget(for: trimmed) {
            return .page(urlString: target)
        }

        return .question(trimmed)
    }

    static func fallbackSearchURL(for question: String, searchEngine: SearchEngine) -> String {
        searchEngine.searchURL(for: question)
    }
}
