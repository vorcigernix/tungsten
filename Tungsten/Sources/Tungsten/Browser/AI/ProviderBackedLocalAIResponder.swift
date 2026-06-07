import Foundation

struct ProviderBackedLocalAIResponder: LocalAIAnswering {
    let provider: @Sendable () -> SidebarAssistantProvider
    let appleResponder: LocalAIAnswering
    let gemmaResponder: LocalAIAnswering
    let codexResponder: LocalAIAnswering
    let claudeResponder: LocalAIAnswering

    init(
        provider: @escaping @Sendable () -> SidebarAssistantProvider,
        appleResponder: LocalAIAnswering = AppleLocalAIResponder(),
        gemmaResponder: LocalAIAnswering = GemmaLocalAIResponder(),
        codexResponder: LocalAIAnswering = ACPAgentResponder.codex(configuration: .codexDefault),
        claudeResponder: LocalAIAnswering = ACPAgentResponder.claude(configuration: .claudeDefault)
    ) {
        self.provider = provider
        self.appleResponder = appleResponder
        self.gemmaResponder = gemmaResponder
        self.codexResponder = codexResponder
        self.claudeResponder = claudeResponder
    }

    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult {
        switch provider() {
        case .appleLocal:
            return await appleResponder.answer(question, pageContext: pageContext)
        case .gemmaLocal:
            return await gemmaResponder.answer(question, pageContext: pageContext)
        case .codexACP:
            return await codexResponder.answer(question, pageContext: pageContext)
        case .claudeACP:
            return await claudeResponder.answer(question, pageContext: pageContext)
        case .disabled:
            return .unavailable("Local AI is disabled, so Tungsten opened AI search instead.")
        }
    }

    func answer(
        _ question: String,
        pageContext: PageContentContext?,
        onPartialAnswer: @escaping @Sendable (String) async -> Void
    ) async -> LocalAIResult {
        switch provider() {
        case .appleLocal:
            return await appleResponder.answer(
                question,
                pageContext: pageContext,
                onPartialAnswer: onPartialAnswer
            )
        case .gemmaLocal:
            return await gemmaResponder.answer(
                question,
                pageContext: pageContext,
                onPartialAnswer: onPartialAnswer
            )
        case .codexACP:
            return await codexResponder.answer(
                question,
                pageContext: pageContext,
                onPartialAnswer: onPartialAnswer
            )
        case .claudeACP:
            return await claudeResponder.answer(
                question,
                pageContext: pageContext,
                onPartialAnswer: onPartialAnswer
            )
        case .disabled:
            return .unavailable("Local AI is disabled, so Tungsten opened AI search instead.")
        }
    }
}
