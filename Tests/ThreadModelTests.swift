import Foundation

@main
struct ThreadModelTests {
    static func main() throws {
        try testDirectURLInputClassifiesAsPage()
        try testBareDomainInputClassifiesAsPage()
        try testLocalhostInputClassifiesAsPage()
        try testNaturalLanguageInputClassifiesAsQuestion()
        try testNaturalLanguageInputDoesNotClassifyAsSearchPage()
        try testThreadAppendsTurnsAndTracksActivePage()
        try testActivePageFallsBackToLastPageWhenNoExplicitActivePage()
        try testActivatePageTurnUpdatesTimestamp()
        try testUpdatePageMetadataCanUpdateURL()
        try testDisplayTitlePrefersFirstQuestionOtherwiseFirstPageHost()
        try testDisplayTitlesTrimAndFallbackForEmptyValues()
        try testBrowserThreadCodableRoundTrip()
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

    static func testNaturalLanguageInputDoesNotClassifyAsSearchPage() throws {
        let searchURL = BrowserInputClassifier.fallbackSearchURL(
            for: "what is tungsten carbide",
            searchEngine: .googleAIMode
        )

        try expect(BrowserInputClassifier.submission(
            for: "what is tungsten carbide",
            searchEngine: .googleAIMode
        ) != .page(urlString: searchURL))
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

        let questionID = thread.appendQuestion("what is tungsten carbide", createdAt: questionDate)
        let assistantID = thread.appendAssistantResponse("A very hard compound.", createdAt: assistantDate)
        let pageID = thread.appendPage(
            urlString: "https://example.com/docs",
            title: "Docs",
            createdAt: pageDate
        )

        try expect(thread.turns.map(\.id) == [questionID, assistantID, pageID])
        try expect(thread.turns.map(\.kind) == [.userQuestion, .assistantResponse, .page])
        try expect(thread.activePageTurnID == pageID)
        try expect(thread.updatedAt == pageDate)
    }

    static func testActivePageFallsBackToLastPageWhenNoExplicitActivePage() throws {
        var thread = BrowserThread(createdAt: Date(timeIntervalSince1970: 10))
        let firstPageID = thread.appendPage(urlString: "https://example.com/first")
        let secondPageID = thread.appendPage(urlString: "https://example.com/second")
        thread.activePageTurnID = nil

        try expect(thread.activePageTurn?.id == secondPageID)
        try expect(thread.activePageTurn?.id != firstPageID)
    }

    static func testActivatePageTurnUpdatesTimestamp() throws {
        var thread = BrowserThread(createdAt: Date(timeIntervalSince1970: 10))
        let firstPageID = thread.appendPage(urlString: "https://example.com/first")
        _ = thread.appendPage(urlString: "https://example.com/second")
        let activationDate = Date(timeIntervalSince1970: 100)

        thread.activatePageTurn(firstPageID, updatedAt: activationDate)

        try expect(thread.activePageTurnID == firstPageID)
        try expect(thread.updatedAt == activationDate)
    }

    static func testUpdatePageMetadataCanUpdateURL() throws {
        var thread = BrowserThread(createdAt: Date(timeIntervalSince1970: 10))
        let pageID = thread.appendPage(urlString: "https://example.com/old", title: "Old")
        let updateDate = Date(timeIntervalSince1970: 50)

        thread.updatePageMetadata(
            turnID: pageID,
            urlString: "https://example.com/new",
            title: "New",
            faviconURLString: "https://example.com/favicon.ico",
            updatedAt: updateDate
        )

        try expect(thread.activePageTurn?.urlString == "https://example.com/new")
        try expect(thread.activePageTurn?.title == "New")
        try expect(thread.activePageTurn?.faviconURLString == "https://example.com/favicon.ico")
        try expect(thread.updatedAt == updateDate)
    }

    static func testDisplayTitlePrefersFirstQuestionOtherwiseFirstPageHost() throws {
        var questionThread = BrowserThread(createdAt: Date(timeIntervalSince1970: 10))
        _ = questionThread.appendPage(urlString: "https://example.com/docs")
        _ = questionThread.appendQuestion("  what is tungsten carbide  ")

        var pageThread = BrowserThread(createdAt: Date(timeIntervalSince1970: 10))
        _ = pageThread.appendPage(urlString: "https://docs.example.com/path")

        try expect(questionThread.displayTitle == "what is tungsten carbide")
        try expect(pageThread.displayTitle == "docs.example.com")
    }

    static func testDisplayTitlesTrimAndFallbackForEmptyValues() throws {
        let longQuestion = "  " + String(repeating: "x", count: 70) + "  "
        var thread = BrowserThread(createdAt: Date(timeIntervalSince1970: 10))
        _ = thread.appendQuestion(longQuestion)

        let blankTurn = BrowserTurn.question("   ")
        let blankPage = BrowserTurn.page(urlString: "", title: "   ")

        try expect(thread.displayTitle == String(repeating: "x", count: 64))
        try expect(blankTurn.displayTitle == "Untitled")
        try expect(blankPage.displayTitle == "Untitled")
    }

    static func testBrowserThreadCodableRoundTrip() throws {
        var thread = BrowserThread(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10),
            isPinned: true
        )
        let questionID = thread.appendQuestion(
            "what is tungsten carbide",
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let pageID = thread.appendPage(
            urlString: "https://example.com/docs",
            title: "Docs",
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            createdAt: Date(timeIntervalSince1970: 30)
        )

        try expect(questionID != pageID)

        let data = try JSONEncoder().encode(thread)
        let decoded = try JSONDecoder().decode(BrowserThread.self, from: data)

        try expect(decoded == thread)
        try expect(decoded.activePageTurnID == pageID)
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
