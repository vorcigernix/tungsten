import Foundation

@main
struct AIResponseCoordinatorTests {
    static func main() async throws {
        try await testLocalSuccessReturnsAssistantAnswer()
        try await testUnavailableLocalAIReturnsFallbackPage()
        try await testProviderBackedResponderUsesAppleResponder()
        try await testProviderBackedResponderReportsDisabledProvider()
        print("AIResponseCoordinatorTests passed")
    }

    static func testLocalSuccessReturnsAssistantAnswer() async throws {
        let coordinator = AIResponseCoordinator(
            localAI: StubLocalAI(result: .answered("Local answer")),
            searchEngine: .perplexity
        )

        let result = await coordinator.response(for: "What is Tungsten?")

        try expect(result == .assistant("Local answer"))
    }

    static func testUnavailableLocalAIReturnsFallbackPage() async throws {
        let reason = "Local AI is unavailable."
        let coordinator = AIResponseCoordinator(
            localAI: StubLocalAI(result: .unavailable(reason)),
            searchEngine: .perplexity
        )

        let result = await coordinator.response(for: "What is Tungsten?")

        try expect(result == .fallbackPage(
            systemMessage: reason,
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
