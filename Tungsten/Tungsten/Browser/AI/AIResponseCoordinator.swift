import Foundation

enum AIResponseResult: Equatable {
    case assistant(String)
    case fallbackPage(systemMessage: String, urlString: String)
}

struct AIResponseCoordinator {
    let localAI: LocalAIAnswering

    func response(
        for question: String,
        searchEngine: SearchEngine,
        pageContext: PageContentContext? = nil
    ) async -> AIResponseResult {
        switch await localAI.answer(question, pageContext: pageContext) {
        case .answered(let answer):
            return .assistant(answer)
        case .unavailable(let reason):
            let systemMessage = pageContext == nil
                ? reason
                : "\(reason) Page content was kept local and was not sent to web search."
            return .fallbackPage(
                systemMessage: systemMessage,
                urlString: BrowserInputClassifier.fallbackSearchURL(for: question, searchEngine: searchEngine)
            )
        }
    }
}
