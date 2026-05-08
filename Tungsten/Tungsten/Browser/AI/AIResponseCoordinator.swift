import Foundation

enum AIResponseResult: Equatable {
    case assistant(String)
    case fallbackPage(systemMessage: String, urlString: String)
}

struct AIResponseCoordinator {
    let localAI: LocalAIAnswering
    let searchEngine: SearchEngine

    func response(for question: String) async -> AIResponseResult {
        switch await localAI.answer(question) {
        case .answered(let answer):
            return .assistant(answer)
        case .unavailable(let reason):
            return .fallbackPage(
                systemMessage: reason,
                urlString: BrowserInputClassifier.fallbackSearchURL(for: question, searchEngine: searchEngine)
            )
        }
    }
}
