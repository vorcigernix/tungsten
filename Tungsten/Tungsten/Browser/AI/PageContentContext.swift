import Foundation

struct PageContentContext: Equatable {
    static let maxContentCharacters = 30_000

    let title: String
    let urlString: String
    let selectedText: String?
    let bodyText: String?

    init(title: String, urlString: String, selectedText: String?, bodyText: String?) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedText = Self.normalized(selectedText)
        self.bodyText = Self.normalized(bodyText)
    }

    var preferredText: String? {
        selectedText ?? bodyText
    }

    var usesSelectedText: Bool {
        selectedText != nil
    }

    func prompt(for question: String) -> String {
        var lines = [
            "Question:",
            question,
            "",
            "Current page:",
            "Title: \(title.isEmpty ? "Untitled" : title)",
            "URL: \(urlString)"
        ]

        if let preferredText {
            lines.append("")
            lines.append(usesSelectedText ? "Selected page text:" : "Page text:")
            lines.append(preferredText)
        }

        return lines.joined(separator: "\n")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        if trimmed.count <= maxContentCharacters {
            return trimmed
        }

        return String(trimmed.prefix(maxContentCharacters))
    }
}
