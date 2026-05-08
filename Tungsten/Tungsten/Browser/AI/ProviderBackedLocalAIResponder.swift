import Foundation

struct ProviderBackedLocalAIResponder: LocalAIAnswering {
    let provider: () -> LocalAIProvider
    let appleResponder: LocalAIAnswering

    init(
        provider: @escaping () -> LocalAIProvider,
        appleResponder: LocalAIAnswering = AppleLocalAIResponder()
    ) {
        self.provider = provider
        self.appleResponder = appleResponder
    }

    func answer(_ question: String) async -> LocalAIResult {
        switch provider() {
        case .apple:
            return await appleResponder.answer(question)
        case .google:
            return await appleResponder.answer(question)
        case .disabled:
            return .unavailable("Local AI is disabled, so Tungsten opened AI search instead.")
        }
    }
}
