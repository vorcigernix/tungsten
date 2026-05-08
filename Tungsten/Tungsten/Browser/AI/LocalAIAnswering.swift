import Foundation

enum LocalAIResult: Equatable {
    case answered(String)
    case unavailable(String)
}

protocol LocalAIAnswering {
    func answer(_ question: String) async -> LocalAIResult
}
