import Foundation

enum LocalAIProvider: String, CaseIterable, Codable, Identifiable {
    case google
    case apple
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google:   return "Google Gemini Nano (pages)"
        case .apple:    return "Apple Local AI"
        case .disabled: return "Disabled"
        }
    }
}
