import Foundation

enum AIResponseResult: Equatable, Sendable {
    case assistant(String)
    case fallbackPage(systemMessage: String, urlString: String)
}

struct AIResponseCoordinator: Sendable {
    let localAI: LocalAIAnswering

    func response(
        for question: String,
        searchEngine: SearchEngine,
        pageContext: PageContentContext? = nil,
        onPartialAnswer: (@Sendable (String) async -> Void)? = nil
    ) async -> AIResponseResult {
        if let quickAnswer = BrowserSidebarQuickAnswer.answer(for: question) {
            if let onPartialAnswer {
                await onPartialAnswer(quickAnswer)
            }
            return .assistant(quickAnswer)
        }

        let result: LocalAIResult
        if let onPartialAnswer {
            result = await localAI.answer(question, pageContext: pageContext, onPartialAnswer: onPartialAnswer)
        } else {
            result = await localAI.answer(question, pageContext: pageContext)
        }

        switch result {
        case .answered(let answer):
            if pageContext != nil,
               LocalAIPrompts.shouldRetryWithoutPageContext(answer),
               case .answered(let generalAnswer) = await answerWithoutPageContext(
                    question,
                    onPartialAnswer: onPartialAnswer
               ),
               generalAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return .assistant(generalAnswer)
            }

            return .assistant(answer)
        case .unavailable(let reason):
            let systemMessage = pageContext == nil
                ? reason
                : "\(reason) Page content was kept local and was not sent to web search."
            return .fallbackPage(
                systemMessage: systemMessage,
                urlString: BrowserInputClassifier.fallbackSearchURL(for: question, searchEngine: searchEngine)
            )
        }
    }

    private func answerWithoutPageContext(
        _ question: String,
        onPartialAnswer: (@Sendable (String) async -> Void)?
    ) async -> LocalAIResult {
        if let onPartialAnswer {
            return await localAI.answer(question, pageContext: nil, onPartialAnswer: onPartialAnswer)
        }

        return await localAI.answer(question, pageContext: nil)
    }
}

private enum BrowserSidebarQuickAnswer {
    static func answer(for question: String) -> String? {
        guard let value = ArithmeticExpressionParser.evaluate(question) else {
            return nil
        }

        return format(value)
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite else {
            return "undefined"
        }

        let rounded = (value * 1_000_000_000_000).rounded() / 1_000_000_000_000
        if rounded == rounded.rounded(),
           rounded >= Double(Int64.min),
           rounded <= Double(Int64.max) {
            return String(Int64(rounded))
        }

        var formatted = String(format: "%.12f", rounded)
        while formatted.last == "0" {
            formatted.removeLast()
        }
        if formatted.last == "." {
            formatted.removeLast()
        }
        return formatted
    }
}

private enum ArithmeticExpressionParser {
    private enum Token: Equatable {
        case number(Double)
        case plus
        case minus
        case multiply
        case divide
        case leftParen
        case rightParen
    }

    static func evaluate(_ question: String) -> Double? {
        guard let tokens = tokenize(question) else {
            return nil
        }
        var parser = Parser(tokens: tokens)
        return parser.parse()
    }

    private static func tokenize(_ question: String) -> [Token]? {
        let normalized = normalizedExpression(question)
        guard normalized.isEmpty == false else {
            return nil
        }

        let parts = normalized.split(separator: " ").map(String.init)
        var tokens = [Token]()
        for part in parts {
            switch part {
            case "+":
                tokens.append(.plus)
            case "-":
                tokens.append(.minus)
            case "*":
                tokens.append(.multiply)
            case "x":
                tokens.append(.multiply)
            case "/":
                tokens.append(.divide)
            case "(":
                tokens.append(.leftParen)
            case ")":
                tokens.append(.rightParen)
            default:
                guard let value = Double(part) else {
                    return nil
                }
                tokens.append(.number(value))
            }
        }

        guard tokens.contains(where: { token in
            token == .plus || token == .minus || token == .multiply || token == .divide
        }) else {
            return nil
        }
        return tokens
    }

    private static func normalizedExpression(_ question: String) -> String {
        var value = question
            .lowercased()
            .replacingOccurrences(of: "?", with: " ")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "×", with: " * ")
            .replacingOccurrences(of: "÷", with: " / ")

        let prefixes = [
            "what is",
            "what's",
            "calculate",
            "compute",
            "solve"
        ]
        for prefix in prefixes where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
            break
        }

        let replacements = [
            ("multiplied by", " * "),
            ("divided by", " / "),
            ("times", " * "),
            ("plus", " + "),
            ("minus", " - "),
            ("over", " / ")
        ]
        for replacement in replacements {
            value = value.replacingOccurrences(of: replacement.0, with: replacement.1)
        }

        for numberWord in numberWords.sorted(by: { $0.key.count > $1.key.count }) {
            value = value.replacingOccurrences(of: numberWord.key, with: " \(numberWord.value) ")
        }

        for symbol in ["+", "-", "*", "/", "(", ")"] {
            value = value.replacingOccurrences(of: symbol, with: " \(symbol) ")
        }

        return value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let numberWords = [
        "zero": "0",
        "one": "1",
        "two": "2",
        "three": "3",
        "four": "4",
        "five": "5",
        "six": "6",
        "seven": "7",
        "eight": "8",
        "nine": "9",
        "ten": "10",
        "eleven": "11",
        "twelve": "12",
        "thirteen": "13",
        "fourteen": "14",
        "fifteen": "15",
        "sixteen": "16",
        "seventeen": "17",
        "eighteen": "18",
        "nineteen": "19",
        "twenty": "20",
        "thirty": "30",
        "forty": "40",
        "fifty": "50",
        "sixty": "60",
        "seventy": "70",
        "eighty": "80",
        "ninety": "90"
    ]

    private struct Parser {
        let tokens: [Token]
        var index = 0

        mutating func parse() -> Double? {
            guard let value = parseExpression(), index == tokens.count else {
                return nil
            }
            return value
        }

        private mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else {
                return nil
            }

            while let token = peek(), token == .plus || token == .minus {
                index += 1
                guard let right = parseTerm() else {
                    return nil
                }
                value = token == .plus ? value + right : value - right
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else {
                return nil
            }

            while let token = peek(), token == .multiply || token == .divide {
                index += 1
                guard let right = parseFactor() else {
                    return nil
                }
                if token == .divide {
                    guard right != 0 else {
                        return .infinity
                    }
                    value /= right
                } else {
                    value *= right
                }
            }
            return value
        }

        private mutating func parseFactor() -> Double? {
            guard let token = peek() else {
                return nil
            }

            switch token {
            case .number(let value):
                index += 1
                return value
            case .minus:
                index += 1
                return parseFactor().map { -$0 }
            case .leftParen:
                index += 1
                guard let value = parseExpression(), peek() == .rightParen else {
                    return nil
                }
                index += 1
                return value
            default:
                return nil
            }
        }

        private func peek() -> Token? {
            guard index < tokens.count else {
                return nil
            }
            return tokens[index]
        }
    }
}
