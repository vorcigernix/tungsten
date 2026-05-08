import Foundation

@main
struct ThreadModelTests {
    static func main() throws {
        try testDirectURLInputClassifiesAsPage()
        try testBareDomainInputClassifiesAsPage()
        try testLocalhostInputClassifiesAsPage()
        try testNaturalLanguageInputClassifiesAsQuestion()
        try testThreadAppendsTurnsAndTracksActivePage()
        try testDisplayTitlePrefersFirstQuestionOtherwiseFirstPageHost()
        print("ThreadModelTests passed")
    }

    static func testDirectURLInputClassifiesAsPage() throws {
        try expect(BrowserInputClassifier.submission(
            for: "https://example.com/docs",
            searchEngine: .googleAIMode
        ) == .page(urlString: "https://example.com/docs"))
    }

    static func testBareDomainInputClassifiesAsPage() throws {
        try expect(BrowserInputClassifier.submission(
            for: "example.com/path",
            searchEngine: .googleAIMode
        ) == .page(urlString: "https://example.com/path"))
    }

    static func testLocalhostInputClassifiesAsPage() throws {
        try expect(BrowserInputClassifier.submission(
            for: "localhost:3000",
            searchEngine: .googleAIMode
        ) == .page(urlString: "http://localhost:3000"))
    }

    static func testNaturalLanguageInputClassifiesAsQuestion() throws {
        try expect(BrowserInputClassifier.submission(
            for: "what is tungsten carbide",
            searchEngine: .googleAIMode
        ) == .question("what is tungsten carbide"))
    }

    static func testThreadAppendsTurnsAndTracksActivePage() throws {
        var thread = BrowserThread(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let questionDate = Date(timeIntervalSince1970: 20)
        let assistantDate = Date(timeIntervalSince1970: 30)
        let pageDate = Date(timeIntervalSince1970: 40)

        let question = thread.appendQuestion("what is tungsten carbide", createdAt: questionDate)
        let assistant = thread.appendAssistantResponse("A very hard compound.", createdAt: assistantDate)
        let page = thread.appendPage(
            urlString: "https://example.com/docs",
            title: "Docs",
            createdAt: pageDate
        )

        try expect(thread.turns == [question, assistant, page])
        try expect(thread.turns.map(\.kind) == [.userQuestion, .assistantResponse, .page])
        try expect(thread.activePageTurnID == page.id)
        try expect(thread.updatedAt == pageDate)
    }

    static func testDisplayTitlePrefersFirstQuestionOtherwiseFirstPageHost() throws {
        var questionThread = BrowserThread(createdAt: Date(timeIntervalSince1970: 10))
        _ = questionThread.appendPage(urlString: "https://example.com/docs")
        _ = questionThread.appendQuestion("what is tungsten carbide")

        var pageThread = BrowserThread(createdAt: Date(timeIntervalSince1970: 10))
        _ = pageThread.appendPage(urlString: "https://docs.example.com/path")

        try expect(questionThread.displayTitle == "what is tungsten carbide")
        try expect(pageThread.displayTitle == "docs.example.com")
    }

    static func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        if condition() == false {
            throw TestFailure(file: "\(file)", line: line)
        }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let file: String
    let line: UInt

    var description: String {
        "Expectation failed at \(file):\(line)"
    }
}
