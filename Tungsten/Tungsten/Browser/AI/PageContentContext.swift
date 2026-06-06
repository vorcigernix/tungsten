import Foundation

struct PageContentContext: Equatable, Sendable {
    static let maxContentCharacters = 12_000

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

    func shouldAttach(to question: String) -> Bool {
        if usesSelectedText {
            return true
        }

        return Self.questionLikelyNeedsPageContext(question)
    }

    static func questionLikelyNeedsPageContext(_ question: String) -> Bool {
        let normalizedQuestion = question
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let paddedQuestion = " \(normalizedQuestion) "

        let pageReferences = [
            " this page ",
            " current page ",
            " page ",
            " this site ",
            " current site ",
            " website ",
            " article ",
            " post ",
            " document ",
            " selection ",
            " selected text ",
            " here "
        ]
        if pageReferences.contains(where: { paddedQuestion.contains($0) }) {
            return true
        }

        let pageTasks = [
            "summarize",
            "summary",
            "tldr",
            "tl dr",
            "explain this",
            "what does this say",
            "what is this about",
            "what is on this",
            "key points",
            "main points",
            "takeaways"
        ]
        return pageTasks.contains { normalizedQuestion.contains($0) }
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
