import Foundation

@main
struct AIResponseCoordinatorTests {
    static func main() async throws {
        try await testLocalSuccessReturnsAssistantAnswer()
        try await testPageContextIsPassedToLocalAI()
        try await testUnavailableLocalAIReturnsFallbackPage()
        try await testFallbackDoesNotSendPageContextToWebSearch()
        try await testFallbackUsesCurrentSearchEngine()
        try await testProviderBackedResponderUsesAppleResponder()
        try await testProviderBackedResponderUsesAppleForGooglePageAIProvider()
        try await testProviderBackedResponderReportsDisabledProvider()
        try testPageContextPrefersSelectedTextAndCapsContent()
        print("AIResponseCoordinatorTests passed")
    }

    static func testLocalSuccessReturnsAssistantAnswer() async throws {
        let coordinator = AIResponseCoordinator(localAI: StubLocalAI(result: .answered("Local answer")))

        let result = await coordinator.response(for: "What is Tungsten?", searchEngine: .perplexity)

        try expect(result == .assistant("Local answer"))
    }

    static func testPageContextIsPassedToLocalAI() async throws {
        let localAI = RecordingLocalAI(result: .answered("Page answer"))
        let coordinator = AIResponseCoordinator(localAI: localAI)
        let pageContext = PageContentContext(
            title: "Docs",
            urlString: "https://example.com/docs",
            selectedText: "Selected text",
            bodyText: "Full page text"
        )

        let result = await coordinator.response(
            for: "What is on this page?",
            searchEngine: .perplexity,
            pageContext: pageContext
        )

        try expect(result == .assistant("Page answer"))
        try expect(localAI.capturedQuestion == "What is on this page?")
        try expect(localAI.capturedPageContext == pageContext)
    }

    static func testUnavailableLocalAIReturnsFallbackPage() async throws {
        let reason = "Local AI is unavailable."
        let coordinator = AIResponseCoordinator(localAI: StubLocalAI(result: .unavailable(reason)))

        let result = await coordinator.response(for: "What is Tungsten?", searchEngine: .perplexity)

        try expect(result == .fallbackPage(
            systemMessage: reason,
            urlString: "https://www.perplexity.ai/search?q=What%20is%20Tungsten?"
        ))
    }

    static func testFallbackDoesNotSendPageContextToWebSearch() async throws {
        let coordinator = AIResponseCoordinator(
            localAI: StubLocalAI(result: .unavailable("Local AI is unavailable."))
        )
        let pageContext = PageContentContext(
            title: "Private doc",
            urlString: "https://example.com/private",
            selectedText: nil,
            bodyText: "do not upload this page text"
        )

        let result = await coordinator.response(
            for: "Summarize this",
            searchEngine: .perplexity,
            pageContext: pageContext
        )

        try expect(result == .fallbackPage(
            systemMessage: "Local AI is unavailable. Page content was kept local and was not sent to web search.",
            urlString: "https://www.perplexity.ai/search?q=Summarize%20this"
        ))
    }

    static func testFallbackUsesCurrentSearchEngine() async throws {
        let coordinator = AIResponseCoordinator(
            localAI: StubLocalAI(result: .unavailable("Local AI is unavailable."))
        )

        let googleResult = await coordinator.response(for: "What is Tungsten?", searchEngine: .googleAIMode)
        let perplexityResult = await coordinator.response(for: "What is Tungsten?", searchEngine: .perplexity)

        try expect(googleResult == .fallbackPage(
            systemMessage: "Local AI is unavailable.",
            urlString: "https://www.google.com/search?q=What%20is%20Tungsten?&udm=50"
        ))
        try expect(perplexityResult == .fallbackPage(
            systemMessage: "Local AI is unavailable.",
            urlString: "https://www.perplexity.ai/search?q=What%20is%20Tungsten?"
        ))
    }

    static func testProviderBackedResponderUsesAppleResponder() async throws {
        let responder = ProviderBackedLocalAIResponder(
            provider: { .apple },
            appleResponder: StubLocalAI(result: .answered("Stub answer"))
        )

        let result = await responder.answer("What is Tungsten?")

        try expect(result == .answered("Stub answer"))
    }

    static func testProviderBackedResponderUsesAppleForGooglePageAIProvider() async throws {
        let responder = ProviderBackedLocalAIResponder(
            provider: { .google },
            appleResponder: StubLocalAI(result: .answered("Apple sidebar answer"))
        )

        let result = await responder.answer("What is Tungsten?")

        try expect(result == .answered("Apple sidebar answer"))
    }

    static func testProviderBackedResponderReportsDisabledProvider() async throws {
        let responder = ProviderBackedLocalAIResponder(
            provider: { .disabled },
            appleResponder: StubLocalAI(result: .answered("Stub answer"))
        )

        let result = await responder.answer("What is Tungsten?")

        try expect(result == .unavailable("Local AI is disabled, so Tungsten opened AI search instead."))
    }

    static func testPageContextPrefersSelectedTextAndCapsContent() throws {
        let longBody = String(repeating: "x", count: PageContentContext.maxContentCharacters + 10)
        let selectedContext = PageContentContext(
            title: " Docs ",
            urlString: " https://example.com ",
            selectedText: "  Selected text  ",
            bodyText: longBody
        )
        let bodyOnlyContext = PageContentContext(
            title: "Docs",
            urlString: "https://example.com",
            selectedText: " ",
            bodyText: longBody
        )

        try expect(selectedContext.preferredText == "Selected text")
        try expect(selectedContext.usesSelectedText)
        try expect(bodyOnlyContext.preferredText?.count == PageContentContext.maxContentCharacters)
        try expect(bodyOnlyContext.usesSelectedText == false)
        try expect(selectedContext.prompt(for: "Summarize").contains("Selected page text:"))
    }

    static func expect(_ condition: @autoclosure () -> Bool) throws {
        if condition() == false {
            throw TestFailure()
        }
    }
}

private struct StubLocalAI: LocalAIAnswering {
    let result: LocalAIResult

    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult {
        result
    }
}

private final class RecordingLocalAI: LocalAIAnswering {
    let result: LocalAIResult
    var capturedQuestion: String?
    var capturedPageContext: PageContentContext?

    init(result: LocalAIResult) {
        self.result = result
    }

    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult {
        capturedQuestion = question
        capturedPageContext = pageContext
        return result
    }
}

private struct TestFailure: Error {}
