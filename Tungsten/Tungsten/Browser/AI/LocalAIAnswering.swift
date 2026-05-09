import Foundation

enum LocalAIResult: Equatable {
    case answered(String)
    case unavailable(String)
}

protocol LocalAIAnswering {
    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult
}

extension LocalAIAnswering {
    func answer(_ question: String) async -> LocalAIResult {
        await answer(question, pageContext: nil)
    }
}
