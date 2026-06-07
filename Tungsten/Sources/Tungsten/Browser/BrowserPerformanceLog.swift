import Foundation

enum BrowserPerformanceLog {
    static func now() -> CFTimeInterval {
        TungstenPerformanceLogNow()
    }

    static func event(_ name: String, metadata: [String: Any] = [:]) {
        TungstenPerformanceLogEvent(name, metadata)
    }

    static func duration(_ name: String, from startTime: CFTimeInterval, metadata: [String: Any] = [:]) {
        TungstenPerformanceLogDuration(name, startTime, metadata)
    }

    static func shortID(_ id: UUID?) -> String {
        guard let id else {
            return "nil"
        }
        return String(id.uuidString.prefix(8))
    }

    static func urlMetadata(_ urlString: String?) -> [String: Any] {
        guard let urlString else {
            return ["has_url": false]
        }

        var metadata: [String: Any] = [
            "has_url": true,
            "url_length": urlString.count
        ]

        let components = URLComponents(string: urlString)
        metadata["scheme"] = components?.scheme ?? "nil"
        metadata["host"] = components?.host ?? "nil"
        return metadata
    }
}
