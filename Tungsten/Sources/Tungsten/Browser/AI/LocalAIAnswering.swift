import Foundation

enum LocalAIResult: Equatable, Sendable {
    case answered(String)
    case unavailable(String)
}

protocol LocalAIAnswering: Sendable {
    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult
    func answer(
        _ question: String,
        pageContext: PageContentContext?,
        onPartialAnswer: @escaping @Sendable (String) async -> Void
    ) async -> LocalAIResult
}

extension LocalAIAnswering {
    func answer(
        _ question: String,
        pageContext: PageContentContext?,
        onPartialAnswer: @escaping @Sendable (String) async -> Void
    ) async -> LocalAIResult {
        let result = await answer(question, pageContext: pageContext)
        if case .answered(let answer) = result {
            await onPartialAnswer(answer)
        }
        return result
    }
}

enum LocalAIPrompts {
    static func instructions(hasPageContext: Bool) -> String {
        if hasPageContext {
            return "Answer browser sidebar questions concisely. Use the current-page context first when it is relevant. If the page context does not contain enough information, answer as a general question when you can, and say that the page did not include the answer. Do not invent page-specific facts or URLs."
        }

        return "Answer browser sidebar questions concisely. Prefer direct answers, include caveats when needed, and do not invent URLs."
    }

    static func prompt(question: String, pageContext: PageContentContext?) -> String {
        pageContext?.prompt(for: question) ?? question
    }

    static func shouldRetryWithoutPageContext(_ answer: String) -> Bool {
        let normalized = answer.lowercased()
        let pageMissMarkers = [
            "does not contain enough information",
            "doesn't contain enough information",
            "page context does not",
            "page does not include",
            "page doesn't include",
            "not mentioned on the page",
            "not in the provided context",
            "not enough information in the page",
            "provided context does not"
        ]

        return pageMissMarkers.contains { normalized.contains($0) }
    }
}

extension LocalAIAnswering {
    func answer(_ question: String) async -> LocalAIResult {
        await answer(question, pageContext: nil)
    }
}
