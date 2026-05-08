import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleLocalAIResponder: LocalAIAnswering {
    func answer(_ question: String) async -> LocalAIResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await answerWithFoundationModels(question)
        } else {
            return .unavailable("Apple local AI is unavailable on this Mac, so Tungsten opened AI search instead.")
        }
        #else
        return .unavailable("Apple local AI is unavailable on this Mac, so Tungsten opened AI search instead.")
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func answerWithFoundationModels(_ question: String) async -> LocalAIResult {
        switch SystemLanguageModel.default.availability {
        case .available:
            do {
                let session = LanguageModelSession(
                    instructions: "Answer browser sidebar questions concisely. Prefer direct answers, include caveats when needed, and do not invent URLs."
                )
                let response = try await session.respond(to: question)
                let answer = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard answer.isEmpty == false else {
                    return .unavailable("Apple local AI returned an empty answer, so Tungsten opened AI search instead.")
                }
                return .answered(answer)
            } catch {
                return .unavailable("Apple local AI could not answer, so Tungsten opened AI search instead.")
            }
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence is not enabled on this Mac, so Tungsten opened AI search instead.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("Apple local AI is not available on this Mac, so Tungsten opened AI search instead.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple local AI is still preparing its model, so Tungsten opened AI search instead.")
        case .unavailable(_):
            return .unavailable("Apple local AI is unavailable on this Mac, so Tungsten opened AI search instead.")
        @unknown default:
            return .unavailable("Apple local AI is unavailable on this Mac, so Tungsten opened AI search instead.")
        }
    }
    #endif
}
