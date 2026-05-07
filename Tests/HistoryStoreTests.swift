import Foundation

@main
struct HistoryStoreTests {
    @MainActor
    static func main() throws {
        try testRecordVisitStoresNewestEntriesFirst()
        try testConsecutiveRepeatedURLUpdatesNewestEntry()
        try testEntriesAreCapped()
        try testClearRemovesEntries()
        try testMalformedURLsAreIgnored()
        print("HistoryStoreTests passed")
    }

    @MainActor
    static func testRecordVisitStoresNewestEntriesFirst() throws {
        let store = makeStore("newest")
        let older = Date(timeIntervalSince1970: 10)
        let newer = Date(timeIntervalSince1970: 20)

        store.recordVisit(urlString: "https://example.com/older", title: "Older", visitedAt: older)
        store.recordVisit(urlString: "https://example.com/newer", title: "Newer", visitedAt: newer)

        try expect(store.entries.map(\.urlString) == [
            "https://example.com/newer",
            "https://example.com/older"
        ])
        try expect(store.entries.map(\.title) == ["Newer", "Older"])
    }

    @MainActor
    static func testConsecutiveRepeatedURLUpdatesNewestEntry() throws {
        let store = makeStore("repeat")
        let firstDate = Date(timeIntervalSince1970: 10)
        let secondDate = Date(timeIntervalSince1970: 20)

        store.recordVisit(urlString: "https://example.com", title: "First", visitedAt: firstDate)
        store.recordVisit(urlString: "https://example.com", title: "Second", visitedAt: secondDate)

        try expect(store.entries.count == 1)
        try expect(store.entries.first?.title == "Second")
        try expect(store.entries.first?.visitedAt == secondDate)
    }

    @MainActor
    static func testEntriesAreCapped() throws {
        let store = makeStore("cap")

        for index in 0..<1_005 {
            store.recordVisit(
                urlString: "https://example.com/page-\(index)",
                title: "Page \(index)",
                visitedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        try expect(store.entries.count == 1_000)
        try expect(store.entries.first?.urlString == "https://example.com/page-1004")
        try expect(store.entries.last?.urlString == "https://example.com/page-5")
    }

    @MainActor
    static func testClearRemovesEntries() throws {
        let store = makeStore("clear")

        store.recordVisit(urlString: "https://example.com", title: "Example", visitedAt: Date())
        try expect(store.entries.isEmpty == false)

        store.clear()
        try expect(store.entries.isEmpty)
    }

    @MainActor
    static func testMalformedURLsAreIgnored() throws {
        let store = makeStore("malformed")

        store.recordVisit(urlString: "not a url", title: "Bad", visitedAt: Date())
        store.recordVisit(urlString: "ftp://example.com/file", title: "FTP", visitedAt: Date())
        store.recordVisit(urlString: "", title: "Empty", visitedAt: Date())

        try expect(store.entries.isEmpty)
    }

    @MainActor
    static func makeStore(_ name: String) -> HistoryStore {
        let suiteName = "TungstenHistoryTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return HistoryStore(userDefaults: defaults, key: "HistoryEntries")
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
