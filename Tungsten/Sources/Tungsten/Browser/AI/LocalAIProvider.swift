import Foundation

enum LocalAIProvider: String, CaseIterable, Codable, Identifiable {
    case gemma
    case apple
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemma:    return "Gemma LiteRT Local"
        case .apple:    return "Apple Local AI"
        case .disabled: return "Disabled"
        }
    }
}

enum SidebarAssistantProvider: String, CaseIterable, Codable, Identifiable {
    case appleLocal
    case gemmaLocal
    case codexACP
    case claudeACP
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleLocal: return "Apple Local AI"
        case .gemmaLocal: return "Gemma LiteRT Local"
        case .codexACP:   return "Codex via ACP"
        case .claudeACP:  return "Claude via ACP"
        case .disabled:   return "Disabled"
        }
    }

    var localAIProvider: LocalAIProvider? {
        switch self {
        case .appleLocal: return .apple
        case .gemmaLocal: return .gemma
        case .disabled:   return .disabled
        case .codexACP, .claudeACP:
            return nil
        }
    }

    init(localAIProvider: LocalAIProvider) {
        switch localAIProvider {
        case .apple:
            self = .appleLocal
        case .gemma:
            self = .gemmaLocal
        case .disabled:
            self = .disabled
        }
    }
}

struct ACPProviderConfiguration: Codable, Equatable, Sendable {
    var command: String
    var arguments: [String]
    var lastError: String?

    static let codexDefault = ACPProviderConfiguration(
        command: "codex-acp",
        arguments: [],
        lastError: nil
    )

    static let claudeDefault = ACPProviderConfiguration(
        command: "claude",
        arguments: ["acp"],
        lastError: nil
    )
}

enum GemmaLocalAIAvailabilityState: String, Codable, Equatable, Sendable {
    case unknown
    case unavailable
    case downloadable
    case downloading
    case available
}

struct GemmaLocalAIAvailability: Codable, Equatable, Sendable {
    var state: GemmaLocalAIAvailabilityState
    var progress: Double?
    var message: String

    static let unknown = GemmaLocalAIAvailability(
        state: .unknown,
        progress: nil,
        message: "Gemma LiteRT Local availability has not been checked."
    )

    static let needsDownload = GemmaLocalAIAvailability(
        state: .downloadable,
        progress: nil,
        message: "Gemma LiteRT Local needs a one-time model download. Downloads about 2.6 GB of model files."
    )

    var canPrepare: Bool {
        state == .downloadable || state == .downloading || state == .unknown
    }
}
