import Foundation

enum BrowserWindowKind: Hashable, Codable {
    case normal
    case incognito

    var sceneID: String {
        switch self {
        case .normal:
            "browser"
        case .incognito:
            "incognito-browser"
        }
    }

    var title: String {
        switch self {
        case .normal:
            "Tungsten"
        case .incognito:
            "Tungsten Private"
        }
    }

    var isIncognito: Bool {
        self == .incognito
    }
}
