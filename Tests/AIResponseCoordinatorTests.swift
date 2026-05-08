import Foundation

@main
struct AIResponseCoordinatorTests {
    static func main() async throws {
        try await testLocalSuccessReturnsAssistantAnswer()
        try await testUnavailableLocalAIReturnsFallbackPage()
        try await testFallbackUsesCurrentSearchEngine()
        try await testProviderBackedResponderUsesAppleResponder()
        try await testProviderBackedResponderUsesAppleForGooglePageAIProvider()
        try await testProviderBackedResponderReportsDisabledProvider()
        print("AIResponseCoordinatorTests passed")
    }

    static func testLocalSuccessReturnsAssistantAnswer() async throws {
        let coordinator = AIResponseCoordinator(localAI: StubLocalAI(result: .answered("Local answer")))

        let result = await coordinator.response(for: "What is Tungsten?", searchEngine: .perplexity)

        try expect(result == .assistant("Local answer"))
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

    static func expect(_ condition: @autoclosure () -> Bool) throws {
        if condition() == false {
            throw TestFailure()
        }
    }
}

private struct StubLocalAI: LocalAIAnswering {
    let result: LocalAIResult

    func answer(_ question: String) async -> LocalAIResult {
        result
    }
}

private struct TestFailure: Error {}
