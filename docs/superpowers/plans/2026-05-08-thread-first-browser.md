# Thread-First Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace classical tab UI/state with persisted chat-like browser threads where URL turns render in CEF and question turns answer in the sidebar or fall back to AI search.

**Architecture:** Add pure thread models, persistence, input classification, and AI response seams before replacing the current `tabs` array. Keep CEF lifecycle behind one live page-session owner so each selected thread has history but only the active page turn owns a `TungstenBrowserController`.

**Tech Stack:** Swift 6, SwiftUI Observation, AppKit, UserDefaults JSON persistence, Objective-C++ CEF bridge, optional Apple Foundation Models via `canImport(FoundationModels)`, existing shell/Swift standalone tests, Xcode file-system synchronized groups.

---

## File Structure

- Create `Tungsten/Tungsten/Browser/Threads/BrowserTurn.swift`: Codable thread turn value types.
- Create `Tungsten/Tungsten/Browser/Threads/BrowserThread.swift`: thread metadata, append/update helpers, derived titles.
- Create `Tungsten/Tungsten/Browser/Threads/BrowserInputClassifier.swift`: direct URL vs question routing.
- Create `Tungsten/Tungsten/Browser/Threads/BrowserThreadStore.swift`: per-window persisted thread snapshots and 30-thread cap.
- Create `Tungsten/Tungsten/Browser/Threads/BrowserThreadStoreScope.swift`: `.persistent(windowSessionID:)` and `.memoryOnly`.
- Create `Tungsten/Tungsten/Browser/Threads/BrowserWindowSessionCoordinator.swift`: decides whether a normal window restores the most recent session or gets a fresh session.
- Create `Tungsten/Tungsten/Browser/Threads/BrowserPageSession.swift`: extracted live CEF page session, replacing internal `BrowserTab` usage.
- Create `Tungsten/Tungsten/Browser/Threads/LivePageSessionHost.swift`: one-live-page owner that creates/closes page sessions.
- Create `Tungsten/Tungsten/Browser/AI/LocalAIProvider.swift`: provider enum shared by Settings and AI runtime.
- Create `Tungsten/Tungsten/Browser/AI/LocalAIAnswering.swift`: async local-answer protocol and result type.
- Create `Tungsten/Tungsten/Browser/AI/AIResponseCoordinator.swift`: local-answer success/fallback decision.
- Create `Tungsten/Tungsten/Browser/AI/AppleLocalAIResponder.swift`: optional Foundation Models responder.
- Create `Tungsten/Tungsten/Browser/AI/ProviderBackedLocalAIResponder.swift`: routes configured provider to Apple local AI or fallback.
- Modify `Tungsten/Tungsten/Browser/AddressResolver.swift`: expose direct navigation target without search fallback.
- Modify `Tungsten/Tungsten/Browser/BrowserModel.swift`: migrate public state/actions from tabs to threads.
- Modify `Tungsten/Tungsten/Browser/BrowserSplitView.swift`: replace tab list with selected-thread timeline, thread switcher, response animation.
- Modify `Tungsten/Tungsten/Browser/BrowserDetailView.swift`: render optional active page session rather than mandatory tab.
- Modify `Tungsten/Tungsten/Browser/BrowserWindowRoot.swift`: create/pass a window-session thread store scope.
- Modify `Tungsten/Tungsten/TungstenApp.swift`: own the shared window-session coordinator.
- Modify `Tungsten/Tungsten/AppPreferences.swift`: move provider enum out and default local AI to Apple.
- Modify `Tungsten/Tungsten/Shortcuts/Core/ShortcutAction.swift`: user-facing labels from Tab to Thread.
- Modify `Tungsten/Tungsten/Shortcuts/ShortcutDispatcher.swift`: dispatch thread actions.
- Create `Tests/ThreadModelTests.swift`: pure model, classification, persistence, cap tests.
- Create `Tests/AIResponseCoordinatorTests.swift`: local success and AI-search fallback tests.
- Create `Tests/ThreadBrowserLifecycleTests.sh`: structural lifecycle checks for one live CEF page.
- Modify `Tests/ShortcutLogicTests.swift`: shortcut labels/action expectations for threads.

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` for `Tungsten/Tungsten`, so new Swift files under that tree should not require `project.pbxproj` edits.

---

### Task 1: Add Thread Models and URL Classification

**Files:**
- Create: `Tests/ThreadModelTests.swift`
- Create: `Tungsten/Tungsten/Browser/Threads/BrowserTurn.swift`
- Create: `Tungsten/Tungsten/Browser/Threads/BrowserThread.swift`
- Create: `Tungsten/Tungsten/Browser/Threads/BrowserInputClassifier.swift`
- Modify: `Tungsten/Tungsten/Browser/AddressResolver.swift`

- [ ] **Step 1: Write failing model and classifier tests**

Create `Tests/ThreadModelTests.swift`:

```swift
import Foundation

@main
struct ThreadModelTests {
    static func main() throws {
        try testDirectURLInputCreatesPageSubmission()
        try testBareDomainCreatesHTTPSPageSubmission()
        try testLocalhostCreatesHTTPPageSubmission()
        try testQuestionInputStaysQuestion()
        try testThreadAppendsQuestionAssistantAndPageTurns()
        try testThreadDerivedTitlePrefersFirstQuestionThenFirstPageHost()
        print("ThreadModelTests passed")
    }

    static func testDirectURLInputCreatesPageSubmission() throws {
        let submission = BrowserInputClassifier.submission(for: "https://example.com/docs", searchEngine: .googleAIMode)
        try expect(submission == .page(urlString: "https://example.com/docs"))
    }

    static func testBareDomainCreatesHTTPSPageSubmission() throws {
        let submission = BrowserInputClassifier.submission(for: "example.com/path", searchEngine: .googleAIMode)
        try expect(submission == .page(urlString: "https://example.com/path"))
    }

    static func testLocalhostCreatesHTTPPageSubmission() throws {
        let submission = BrowserInputClassifier.submission(for: "localhost:3000", searchEngine: .googleAIMode)
        try expect(submission == .page(urlString: "http://localhost:3000"))
    }

    static func testQuestionInputStaysQuestion() throws {
        let submission = BrowserInputClassifier.submission(for: "what is tungsten carbide", searchEngine: .googleAIMode)
        try expect(submission == .question("what is tungsten carbide"))
    }

    static func testThreadAppendsQuestionAssistantAndPageTurns() throws {
        var thread = BrowserThread(createdAt: Date(timeIntervalSince1970: 10))
        let questionID = thread.appendQuestion("What is CEF?", createdAt: Date(timeIntervalSince1970: 11))
        let responseID = thread.appendAssistantResponse("CEF embeds Chromium.", createdAt: Date(timeIntervalSince1970: 12))
        let pageID = thread.appendPage(urlString: "https://example.com", title: "Example", createdAt: Date(timeIntervalSince1970: 13))

        try expect(thread.turns.map(\.id) == [questionID, responseID, pageID])
        try expect(thread.turns.map(\.kind) == [.userQuestion, .assistantResponse, .page])
        try expect(thread.activePageTurnID == pageID)
        try expect(thread.updatedAt == Date(timeIntervalSince1970: 13))
    }

    static func testThreadDerivedTitlePrefersFirstQuestionThenFirstPageHost() throws {
        var questionThread = BrowserThread(createdAt: Date(timeIntervalSince1970: 20))
        questionThread.appendQuestion("How do local browser models work?", createdAt: Date(timeIntervalSince1970: 21))
        try expect(questionThread.displayTitle == "How do local browser models work?")

        var pageThread = BrowserThread(createdAt: Date(timeIntervalSince1970: 30))
        pageThread.appendPage(urlString: "https://developer.apple.com/documentation/foundationmodels", title: "", createdAt: Date(timeIntervalSince1970: 31))
        try expect(pageThread.displayTitle == "developer.apple.com")
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
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swiftc \
  Tungsten/Tungsten/Browser/SearchEngine.swift \
  Tungsten/Tungsten/Browser/AddressResolver.swift \
  Tungsten/Tungsten/Browser/Threads/*.swift \
  Tests/ThreadModelTests.swift \
  -o /tmp/TungstenThreadModelTests && /tmp/TungstenThreadModelTests
```

Expected: FAIL with missing `BrowserInputClassifier`, `BrowserThread`, or `BrowserTurn` symbols.

- [ ] **Step 3: Expose direct navigation resolution**

In `Tungsten/Tungsten/Browser/AddressResolver.swift`, add this public helper and reuse it from `navigationTarget`:

```swift
static func directNavigationTarget(for input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else {
        return nil
    }

    if let directURL = directURL(from: trimmed) {
        return directURL
    }

    if let scheme = defaultSchemeForAddress(trimmed) {
        return "\(scheme)://\(trimmed)"
    }

    return nil
}
```

Then make `navigationTarget` call it before falling back to search:

```swift
static func navigationTarget(for input: String, searchEngine: SearchEngine = .googleAIMode) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else {
        return nil
    }

    if let directTarget = directNavigationTarget(for: trimmed) {
        return directTarget
    }

    return searchEngine.searchURL(for: trimmed)
}
```

- [ ] **Step 4: Create `BrowserTurn.swift`**

Create `Tungsten/Tungsten/Browser/Threads/BrowserTurn.swift`:

```swift
import Foundation

enum BrowserTurnKind: String, Codable, Equatable {
    case userQuestion
    case assistantResponse
    case page
    case system
}

struct BrowserTurn: Identifiable, Codable, Equatable {
    typealias ID = UUID

    let id: ID
    var kind: BrowserTurnKind
    var text: String
    var urlString: String?
    var title: String
    var faviconURLString: String?
    var createdAt: Date

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty == false {
            return trimmedTitle
        }

        if let urlString,
           let host = URLComponents(string: urlString)?.host,
           host.isEmpty == false {
            return host
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? "Untitled" : trimmedText
    }

    static func question(_ text: String, id: ID = ID(), createdAt: Date = Date()) -> BrowserTurn {
        BrowserTurn(id: id, kind: .userQuestion, text: text, urlString: nil, title: "", faviconURLString: nil, createdAt: createdAt)
    }

    static func assistant(_ text: String, id: ID = ID(), createdAt: Date = Date()) -> BrowserTurn {
        BrowserTurn(id: id, kind: .assistantResponse, text: text, urlString: nil, title: "", faviconURLString: nil, createdAt: createdAt)
    }

    static func system(_ text: String, id: ID = ID(), createdAt: Date = Date()) -> BrowserTurn {
        BrowserTurn(id: id, kind: .system, text: text, urlString: nil, title: "", faviconURLString: nil, createdAt: createdAt)
    }

    static func page(
        urlString: String,
        title: String = "",
        faviconURLString: String? = nil,
        id: ID = ID(),
        createdAt: Date = Date()
    ) -> BrowserTurn {
        BrowserTurn(
            id: id,
            kind: .page,
            text: "",
            urlString: urlString,
            title: title,
            faviconURLString: faviconURLString,
            createdAt: createdAt
        )
    }
}
```

- [ ] **Step 5: Create `BrowserThread.swift`**

Create `Tungsten/Tungsten/Browser/Threads/BrowserThread.swift`:

```swift
import Foundation

struct BrowserThread: Identifiable, Codable, Equatable {
    typealias ID = UUID

    let id: ID
    var createdAt: Date
    var updatedAt: Date
    var turns: [BrowserTurn]
    var activePageTurnID: BrowserTurn.ID?
    var isPinned: Bool

    init(
        id: ID = ID(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        turns: [BrowserTurn] = [],
        activePageTurnID: BrowserTurn.ID? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.turns = turns
        self.activePageTurnID = activePageTurnID
        self.isPinned = isPinned
    }

    var displayTitle: String {
        if let question = turns.first(where: { $0.kind == .userQuestion })?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           question.isEmpty == false {
            return String(question.prefix(64))
        }

        if let pageTurn = turns.first(where: { $0.kind == .page }) {
            return pageTurn.displayTitle
        }

        return "New Thread"
    }

    var activePageTurn: BrowserTurn? {
        guard let activePageTurnID else {
            return turns.last { $0.kind == .page }
        }

        return turns.first { $0.id == activePageTurnID }
    }

    @discardableResult
    mutating func appendQuestion(_ text: String, createdAt: Date = Date()) -> BrowserTurn.ID {
        append(.question(text, createdAt: createdAt), updatedAt: createdAt)
    }

    @discardableResult
    mutating func appendAssistantResponse(_ text: String, createdAt: Date = Date()) -> BrowserTurn.ID {
        append(.assistant(text, createdAt: createdAt), updatedAt: createdAt)
    }

    @discardableResult
    mutating func appendSystemMessage(_ text: String, createdAt: Date = Date()) -> BrowserTurn.ID {
        append(.system(text, createdAt: createdAt), updatedAt: createdAt)
    }

    @discardableResult
    mutating func appendPage(
        urlString: String,
        title: String = "",
        faviconURLString: String? = nil,
        createdAt: Date = Date()
    ) -> BrowserTurn.ID {
        let id = append(
            .page(urlString: urlString, title: title, faviconURLString: faviconURLString, createdAt: createdAt),
            updatedAt: createdAt
        )
        activePageTurnID = id
        return id
    }

    mutating func activatePageTurn(_ turnID: BrowserTurn.ID, updatedAt: Date = Date()) {
        guard turns.contains(where: { $0.id == turnID && $0.kind == .page }) else {
            return
        }

        activePageTurnID = turnID
        self.updatedAt = updatedAt
    }

    mutating func updatePageMetadata(
        turnID: BrowserTurn.ID,
        urlString: String? = nil,
        title: String? = nil,
        faviconURLString: String? = nil,
        updatedAt: Date = Date()
    ) {
        guard let index = turns.firstIndex(where: { $0.id == turnID && $0.kind == .page }) else {
            return
        }

        if let urlString {
            turns[index].urlString = urlString
        }
        if let title {
            turns[index].title = title
        }
        if let faviconURLString {
            turns[index].faviconURLString = faviconURLString
        }
        self.updatedAt = updatedAt
    }

    private mutating func append(_ turn: BrowserTurn, updatedAt: Date) -> BrowserTurn.ID {
        turns.append(turn)
        self.updatedAt = updatedAt
        return turn.id
    }
}
```

- [ ] **Step 6: Create `BrowserInputClassifier.swift`**

Create `Tungsten/Tungsten/Browser/Threads/BrowserInputClassifier.swift`:

```swift
import Foundation

enum BrowserInputSubmission: Equatable {
    case page(urlString: String)
    case question(String)
}

enum BrowserInputClassifier {
    static func submission(for input: String, searchEngine: SearchEngine) -> BrowserInputSubmission? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        if let directTarget = AddressResolver.directNavigationTarget(for: trimmed) {
            return .page(urlString: directTarget)
        }

        return .question(trimmed)
    }

    static func fallbackSearchURL(for question: String, searchEngine: SearchEngine) -> String {
        searchEngine.searchURL(for: question)
    }
}
```

- [ ] **Step 7: Run tests and verify GREEN**

Run:

```bash
swiftc \
  Tungsten/Tungsten/Browser/SearchEngine.swift \
  Tungsten/Tungsten/Browser/AddressResolver.swift \
  Tungsten/Tungsten/Browser/Threads/*.swift \
  Tests/ThreadModelTests.swift \
  -o /tmp/TungstenThreadModelTests && /tmp/TungstenThreadModelTests
```

Expected: PASS with `ThreadModelTests passed`.

- [ ] **Step 8: Commit**

```bash
git add Tests/ThreadModelTests.swift Tungsten/Tungsten/Browser/AddressResolver.swift Tungsten/Tungsten/Browser/Threads/BrowserTurn.swift Tungsten/Tungsten/Browser/Threads/BrowserThread.swift Tungsten/Tungsten/Browser/Threads/BrowserInputClassifier.swift
git commit -m "feat: add browser thread model"
```

---

### Task 2: Add Per-Window Thread Persistence

**Files:**
- Modify: `Tests/ThreadModelTests.swift`
- Create: `Tungsten/Tungsten/Browser/Threads/BrowserThreadStoreScope.swift`
- Create: `Tungsten/Tungsten/Browser/Threads/BrowserThreadStore.swift`

- [ ] **Step 1: Add failing persistence tests**

Append these calls in `ThreadModelTests.main()` before the final print:

```swift
        try testPersistentStoreCapsThreadsAtThirty()
        try testPersistentStorePreservesSelectedThreadWhenCapping()
        try testMemoryOnlyStoreDoesNotWriteDefaults()
        try testMostRecentWindowSessionIsTracked()
```

Add these test methods inside `ThreadModelTests`:

```swift
static func testPersistentStoreCapsThreadsAtThirty() throws {
    let suiteName = "TungstenThreadTests.cap.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = BrowserThreadStore(userDefaults: defaults, scope: .persistent(windowSessionID: "window-a"))

    var threads: [BrowserThread] = []
    for index in 0..<31 {
        var thread = BrowserThread(createdAt: Date(timeIntervalSince1970: TimeInterval(index)))
        thread.appendQuestion("Question \(index)", createdAt: Date(timeIntervalSince1970: TimeInterval(index)))
        threads.append(thread)
    }

    let savedSelection = threads.last!.id
    store.save(threads: threads, selectedThreadID: savedSelection)
    let snapshot = store.load()

    try expect(snapshot.threads.count == 30)
    try expect(snapshot.threads.first?.displayTitle == "Question 1")
    try expect(snapshot.threads.last?.displayTitle == "Question 30")
    try expect(snapshot.selectedThreadID == savedSelection)
}

static func testMemoryOnlyStoreDoesNotWriteDefaults() throws {
    let suiteName = "TungstenThreadTests.memory.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = BrowserThreadStore(userDefaults: defaults, scope: .memoryOnly)

    var thread = BrowserThread()
    thread.appendQuestion("Private question")
    store.save(threads: [thread], selectedThreadID: thread.id)

    try expect(store.load().threads.isEmpty)
    try expect(defaults.dictionaryRepresentation().keys.contains { $0.contains("Tungsten.BrowserThreads") } == false)
}

static func testPersistentStorePreservesSelectedThreadWhenCapping() throws {
    let suiteName = "TungstenThreadTests.selected-cap.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = BrowserThreadStore(userDefaults: defaults, scope: .persistent(windowSessionID: "window-selected"))

    var threads: [BrowserThread] = []
    for index in 0..<31 {
        var thread = BrowserThread(createdAt: Date(timeIntervalSince1970: TimeInterval(index)))
        thread.appendQuestion("Question \(index)", createdAt: Date(timeIntervalSince1970: TimeInterval(index)))
        threads.append(thread)
    }

    let selectedOldest = threads[0].id
    store.save(threads: threads, selectedThreadID: selectedOldest)
    let snapshot = store.load()

    try expect(snapshot.threads.count == 30)
    try expect(snapshot.threads.contains { $0.id == selectedOldest })
    try expect(snapshot.selectedThreadID == selectedOldest)
}

static func testMostRecentWindowSessionIsTracked() throws {
    let suiteName = "TungstenThreadTests.sessions.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    BrowserThreadStore.markWindowSessionActive("window-old", userDefaults: defaults, activeAt: Date(timeIntervalSince1970: 1))
    BrowserThreadStore.markWindowSessionActive("window-new", userDefaults: defaults, activeAt: Date(timeIntervalSince1970: 2))

    try expect(BrowserThreadStore.mostRecentWindowSessionID(userDefaults: defaults) == "window-new")
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swiftc \
  Tungsten/Tungsten/Browser/SearchEngine.swift \
  Tungsten/Tungsten/Browser/AddressResolver.swift \
  Tungsten/Tungsten/Browser/Threads/*.swift \
  Tests/ThreadModelTests.swift \
  -o /tmp/TungstenThreadModelTests && /tmp/TungstenThreadModelTests
```

Expected: FAIL with missing `BrowserThreadStore` or `BrowserThreadStoreScope`.

- [ ] **Step 3: Create persistence scope**

Create `Tungsten/Tungsten/Browser/Threads/BrowserThreadStoreScope.swift`:

```swift
import Foundation

enum BrowserThreadStoreScope: Equatable {
    case persistent(windowSessionID: String)
    case memoryOnly
}
```

- [ ] **Step 4: Create thread store**

Create `Tungsten/Tungsten/Browser/Threads/BrowserThreadStore.swift`:

```swift
import Foundation

struct BrowserThreadSnapshot: Codable, Equatable {
    var threads: [BrowserThread]
    var selectedThreadID: BrowserThread.ID?
}

private struct BrowserWindowSessionRecord: Codable, Equatable {
    var id: String
    var activeAt: Date
}

final class BrowserThreadStore {
    private static let maxThreads = 30
    private static let sessionIndexKey = "Tungsten.BrowserThreadWindowSessions.v1"
    private static let snapshotKeyPrefix = "Tungsten.BrowserThreads.v1"

    private let userDefaults: UserDefaults
    private let scope: BrowserThreadStoreScope

    init(userDefaults: UserDefaults = .standard, scope: BrowserThreadStoreScope) {
        self.userDefaults = userDefaults
        self.scope = scope
    }

    func load() -> BrowserThreadSnapshot {
        guard case let .persistent(windowSessionID) = scope else {
            return BrowserThreadSnapshot(threads: [], selectedThreadID: nil)
        }

        guard let data = userDefaults.data(forKey: Self.snapshotKey(for: windowSessionID)) else {
            return BrowserThreadSnapshot(threads: [], selectedThreadID: nil)
        }

        do {
            return try JSONDecoder().decode(BrowserThreadSnapshot.self, from: data)
        } catch {
            userDefaults.removeObject(forKey: Self.snapshotKey(for: windowSessionID))
            return BrowserThreadSnapshot(threads: [], selectedThreadID: nil)
        }
    }

    func save(threads: [BrowserThread], selectedThreadID: BrowserThread.ID?) {
        guard case let .persistent(windowSessionID) = scope else {
            return
        }

        let cappedThreads = Self.capped(threads, preserving: selectedThreadID)
        let selectedID = cappedThreads.contains(where: { $0.id == selectedThreadID }) ? selectedThreadID : cappedThreads.last?.id
        let snapshot = BrowserThreadSnapshot(threads: cappedThreads, selectedThreadID: selectedID)

        do {
            let data = try JSONEncoder().encode(snapshot)
            userDefaults.set(data, forKey: Self.snapshotKey(for: windowSessionID))
            Self.markWindowSessionActive(windowSessionID, userDefaults: userDefaults)
        } catch {
            userDefaults.removeObject(forKey: Self.snapshotKey(for: windowSessionID))
        }
    }

    static func makeWindowSessionID() -> String {
        UUID().uuidString
    }

    static func mostRecentWindowSessionID(userDefaults: UserDefaults = .standard) -> String? {
        sessionRecords(userDefaults: userDefaults)
            .sorted { $0.activeAt > $1.activeAt }
            .first?
            .id
    }

    static func markWindowSessionActive(_ id: String, userDefaults: UserDefaults = .standard, activeAt: Date = Date()) {
        var records = sessionRecords(userDefaults: userDefaults).filter { $0.id != id }
        records.append(BrowserWindowSessionRecord(id: id, activeAt: activeAt))
        records.sort { $0.activeAt > $1.activeAt }

        if let data = try? JSONEncoder().encode(records) {
            userDefaults.set(data, forKey: sessionIndexKey)
        }
    }

    private static func capped(_ threads: [BrowserThread], preserving selectedThreadID: BrowserThread.ID?) -> [BrowserThread] {
        guard threads.count > maxThreads else {
            return threads
        }

        var cappedThreads = Array(threads.suffix(maxThreads))
        guard
            let selectedThreadID,
            cappedThreads.contains(where: { $0.id == selectedThreadID }) == false,
            let selectedThread = threads.first(where: { $0.id == selectedThreadID })
        else {
            return cappedThreads
        }

        cappedThreads.removeFirst()
        cappedThreads.insert(selectedThread, at: 0)
        return cappedThreads
    }

    private static func snapshotKey(for windowSessionID: String) -> String {
        "\(snapshotKeyPrefix).\(windowSessionID)"
    }

    private static func sessionRecords(userDefaults: UserDefaults) -> [BrowserWindowSessionRecord] {
        guard let data = userDefaults.data(forKey: sessionIndexKey) else {
            return []
        }

        return (try? JSONDecoder().decode([BrowserWindowSessionRecord].self, from: data)) ?? []
    }
}
```

- [ ] **Step 5: Run tests and verify GREEN**

Run:

```bash
swiftc \
  Tungsten/Tungsten/Browser/SearchEngine.swift \
  Tungsten/Tungsten/Browser/AddressResolver.swift \
  Tungsten/Tungsten/Browser/Threads/*.swift \
  Tests/ThreadModelTests.swift \
  -o /tmp/TungstenThreadModelTests && /tmp/TungstenThreadModelTests
```

Expected: PASS with `ThreadModelTests passed`.

- [ ] **Step 6: Commit**

```bash
git add Tests/ThreadModelTests.swift Tungsten/Tungsten/Browser/Threads/BrowserThreadStoreScope.swift Tungsten/Tungsten/Browser/Threads/BrowserThreadStore.swift
git commit -m "feat: persist browser threads per window"
```

---

### Task 3: Add AI Response and Fallback Seams

**Files:**
- Create: `Tests/AIResponseCoordinatorTests.swift`
- Create: `Tungsten/Tungsten/Browser/AI/LocalAIProvider.swift`
- Create: `Tungsten/Tungsten/Browser/AI/LocalAIAnswering.swift`
- Create: `Tungsten/Tungsten/Browser/AI/AIResponseCoordinator.swift`
- Create: `Tungsten/Tungsten/Browser/AI/AppleLocalAIResponder.swift`
- Create: `Tungsten/Tungsten/Browser/AI/ProviderBackedLocalAIResponder.swift`
- Modify: `Tungsten/Tungsten/AppPreferences.swift`
- Modify: `Tests/LocalAISettingsTests.sh`

- [ ] **Step 1: Write failing AI coordinator tests**

Create `Tests/AIResponseCoordinatorTests.swift`:

```swift
import Foundation

@main
struct AIResponseCoordinatorTests {
    static func main() async throws {
        try await testLocalSuccessReturnsAssistantText()
        try await testUnavailableLocalAIProducesSystemMessageAndFallbackPage()
        try await testProviderBackedResponderUsesAppleProvider()
        try await testProviderBackedResponderFallsBackForDisabledProvider()
        print("AIResponseCoordinatorTests passed")
    }

    static func testLocalSuccessReturnsAssistantText() async throws {
        let coordinator = AIResponseCoordinator(
            localAI: StubLocalAI(result: .answered("Local answer")),
            searchEngine: .googleAIMode
        )

        let result = await coordinator.response(for: "What is Tungsten?")

        try expect(result == .assistant("Local answer"))
    }

    static func testUnavailableLocalAIProducesSystemMessageAndFallbackPage() async throws {
        let coordinator = AIResponseCoordinator(
            localAI: StubLocalAI(result: .unavailable("Apple local AI is unavailable.")),
            searchEngine: .perplexity
        )

        let result = await coordinator.response(for: "What is Tungsten?")

        try expect(result == .fallbackPage(
            systemMessage: "Apple local AI is unavailable.",
            urlString: "https://www.perplexity.ai/search?q=What%20is%20Tungsten%3F"
        ))
    }

    static func testProviderBackedResponderUsesAppleProvider() async throws {
        let responder = ProviderBackedLocalAIResponder(
            provider: { .apple },
            appleResponder: StubLocalAI(result: .answered("Apple answer"))
        )

        try expect(await responder.answer("Question") == .answered("Apple answer"))
    }

    static func testProviderBackedResponderFallsBackForDisabledProvider() async throws {
        let responder = ProviderBackedLocalAIResponder(
            provider: { .disabled },
            appleResponder: StubLocalAI(result: .answered("Unused"))
        )

        try expect(await responder.answer("Question") == .unavailable("Local AI is disabled, so Tungsten opened AI search instead."))
    }

    static func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        if condition() == false {
            throw TestFailure(file: "\(file)", line: line)
        }
    }
}

struct StubLocalAI: LocalAIAnswering {
    let result: LocalAIResult

    func answer(_ question: String) async -> LocalAIResult {
        result
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let file: String
    let line: UInt

    var description: String {
        "Expectation failed at \(file):\(line)"
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swiftc \
  Tungsten/Tungsten/Browser/SearchEngine.swift \
  Tungsten/Tungsten/Browser/AddressResolver.swift \
  Tungsten/Tungsten/Browser/Threads/*.swift \
  Tungsten/Tungsten/Browser/AI/*.swift \
  Tests/AIResponseCoordinatorTests.swift \
  -o /tmp/TungstenAIResponseCoordinatorTests && /tmp/TungstenAIResponseCoordinatorTests
```

Expected: FAIL with missing `AIResponseCoordinator`, `LocalAIAnswering`, or `LocalAIResult`.

- [ ] **Step 3: Move provider enum to AI folder**

Create `Tungsten/Tungsten/Browser/AI/LocalAIProvider.swift`:

```swift
import Foundation

enum LocalAIProvider: String, CaseIterable, Codable, Identifiable {
    case google
    case apple
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google:   return "Google Local AI"
        case .apple:    return "Apple Local AI"
        case .disabled: return "Disabled"
        }
    }
}
```

Remove the duplicate `LocalAIProvider` enum from `AppPreferences.swift`. Keep `AppPreferences.localAIProvider` using this moved type.

In `AppPreferences.init`, change the default provider from disabled to Apple:

```swift
if let raw = userDefaults.string(forKey: Self.localAIProviderKey),
   let stored = LocalAIProvider(rawValue: raw) {
    self.localAIProvider = stored
} else {
    self.localAIProvider = .apple
}
```

Update `Tests/LocalAISettingsTests.sh` to look for the provider enum in `Tungsten/Tungsten/Browser/AI/LocalAIProvider.swift`:

```bash
provider_file="Tungsten/Tungsten/Browser/AI/LocalAIProvider.swift"
require_pattern "$provider_file" "enum LocalAIProvider" "LocalAIProvider model"
require_pattern "$provider_file" "case google" "Google Local AI option"
require_pattern "$provider_file" "case apple" "Apple Local AI option"
require_pattern "$provider_file" "case disabled" "Disabled Local AI option"
require_pattern "$preferences_file" "self.localAIProvider = \\.apple" "Apple Local AI default"
```

- [ ] **Step 4: Create local AI protocol**

Create `Tungsten/Tungsten/Browser/AI/LocalAIAnswering.swift`:

```swift
import Foundation

enum LocalAIResult: Equatable {
    case answered(String)
    case unavailable(String)
}

protocol LocalAIAnswering {
    func answer(_ question: String) async -> LocalAIResult
}
```

- [ ] **Step 5: Create AI response coordinator**

Create `Tungsten/Tungsten/Browser/AI/AIResponseCoordinator.swift`:

```swift
import Foundation

enum AIResponseResult: Equatable {
    case assistant(String)
    case fallbackPage(systemMessage: String, urlString: String)
}

struct AIResponseCoordinator {
    let localAI: LocalAIAnswering
    let searchEngine: SearchEngine

    func response(for question: String) async -> AIResponseResult {
        switch await localAI.answer(question) {
        case .answered(let text):
            return .assistant(text)
        case .unavailable(let reason):
            return .fallbackPage(
                systemMessage: reason,
                urlString: BrowserInputClassifier.fallbackSearchURL(for: question, searchEngine: searchEngine)
            )
        }
    }
}
```

- [ ] **Step 6: Create Apple local AI responder**

Create `Tungsten/Tungsten/Browser/AI/AppleLocalAIResponder.swift`:

```swift
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleLocalAIResponder: LocalAIAnswering {
    func answer(_ question: String) async -> LocalAIResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await FoundationModelsResponder().answer(question)
        }
        #endif

        return .unavailable("Apple local AI is unavailable on this Mac, so Tungsten opened AI search instead.")
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private struct FoundationModelsResponder {
    func answer(_ question: String) async -> LocalAIResult {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            break
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence is off, so Tungsten opened AI search instead.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("Apple local AI is not supported on this Mac, so Tungsten opened AI search instead.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple local AI is still preparing, so Tungsten opened AI search instead.")
        case .unavailable(_):
            return .unavailable("Apple local AI is unavailable, so Tungsten opened AI search instead.")
        @unknown default:
            return .unavailable("Apple local AI is unavailable, so Tungsten opened AI search instead.")
        }

        do {
            let session = LanguageModelSession(
                instructions: "Answer browser sidebar questions concisely. Prefer direct answers, include caveats when needed, and do not invent URLs."
            )
            let response = try await session.respond(to: question)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return .unavailable("Apple local AI returned an empty response, so Tungsten opened AI search instead.")
            }
            return .answered(text)
        } catch {
            return .unavailable("Apple local AI failed to respond, so Tungsten opened AI search instead.")
        }
    }
}
#endif
```

- [ ] **Step 7: Create provider-backed responder**

Create `Tungsten/Tungsten/Browser/AI/ProviderBackedLocalAIResponder.swift`:

```swift
import Foundation

struct ProviderBackedLocalAIResponder: LocalAIAnswering {
    let provider: () -> LocalAIProvider
    let appleResponder: LocalAIAnswering

    init(
        provider: @escaping () -> LocalAIProvider,
        appleResponder: LocalAIAnswering = AppleLocalAIResponder()
    ) {
        self.provider = provider
        self.appleResponder = appleResponder
    }

    func answer(_ question: String) async -> LocalAIResult {
        switch provider() {
        case .apple:
            return await appleResponder.answer(question)
        case .google:
            return .unavailable("Google local AI is enabled for Chromium pages; Tungsten opened AI search for this sidebar question.")
        case .disabled:
            return .unavailable("Local AI is disabled, so Tungsten opened AI search instead.")
        }
    }
}
```

- [ ] **Step 8: Run AI tests and verify GREEN**

Run:

```bash
swiftc \
  Tungsten/Tungsten/Browser/SearchEngine.swift \
  Tungsten/Tungsten/Browser/AddressResolver.swift \
  Tungsten/Tungsten/Browser/Threads/*.swift \
  Tungsten/Tungsten/Browser/AI/*.swift \
  Tests/AIResponseCoordinatorTests.swift \
  -o /tmp/TungstenAIResponseCoordinatorTests && /tmp/TungstenAIResponseCoordinatorTests
```

Expected: PASS with `AIResponseCoordinatorTests passed`.

- [ ] **Step 9: Run Local AI settings structural test**

Run:

```bash
bash Tests/LocalAISettingsTests.sh
```

Expected: PASS with `LocalAISettingsTests passed`.

- [ ] **Step 10: Commit**

```bash
git add Tests/AIResponseCoordinatorTests.swift Tests/LocalAISettingsTests.sh Tungsten/Tungsten/AppPreferences.swift Tungsten/Tungsten/Browser/AI/LocalAIProvider.swift Tungsten/Tungsten/Browser/AI/LocalAIAnswering.swift Tungsten/Tungsten/Browser/AI/AIResponseCoordinator.swift Tungsten/Tungsten/Browser/AI/AppleLocalAIResponder.swift Tungsten/Tungsten/Browser/AI/ProviderBackedLocalAIResponder.swift
git commit -m "feat: add local ai fallback coordinator"
```

---

### Task 4: Extract One Live Page Session

**Files:**
- Create: `Tests/ThreadBrowserLifecycleTests.sh`
- Create: `Tungsten/Tungsten/Browser/Threads/BrowserPageSession.swift`
- Create: `Tungsten/Tungsten/Browser/Threads/LivePageSessionHost.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`

- [ ] **Step 1: Write failing structural lifecycle test**

Create `Tests/ThreadBrowserLifecycleTests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

model_file="Tungsten/Tungsten/Browser/BrowserModel.swift"
page_session_file="Tungsten/Tungsten/Browser/Threads/BrowserPageSession.swift"
host_file="Tungsten/Tungsten/Browser/Threads/LivePageSessionHost.swift"

if [[ ! -f "$page_session_file" ]]; then
    echo "Missing BrowserPageSession extracted from the old BrowserTab live CEF wrapper." >&2
    exit 1
fi

if [[ ! -f "$host_file" ]]; then
    echo "Missing LivePageSessionHost one-live-page owner." >&2
    exit 1
fi

if ! rg -q "final class BrowserPageSession" "$page_session_file"; then
    echo "BrowserPageSession must own the live TungstenBrowserController." >&2
    exit 1
fi

if ! rg -q "final class LivePageSessionHost" "$host_file"; then
    echo "LivePageSessionHost must exist as the single active CEF owner." >&2
    exit 1
fi

if ! rg -q "func activate\\(pageTurn:.*BrowserTurn" "$host_file"; then
    echo "LivePageSessionHost must activate a BrowserTurn page turn." >&2
    exit 1
fi

if ! rg -q "activePageSession" "$model_file"; then
    echo "BrowserModel must expose the active page session for BrowserDetailView." >&2
    exit 1
fi

echo "ThreadBrowserLifecycleTests passed"
```

- [ ] **Step 2: Run test and verify RED**

Run:

```bash
bash Tests/ThreadBrowserLifecycleTests.sh
```

Expected: FAIL because the extracted page session and live-page host do not exist yet.

- [ ] **Step 3: Extract `BrowserPageSession`**

Move the current `BrowserTab` class and `BrowserControllerObserver` from `BrowserModel.swift` into `Tungsten/Tungsten/Browser/Threads/BrowserPageSession.swift`. Rename `BrowserTab` to `BrowserPageSession` and keep these public properties/methods:

```swift
@Observable @MainActor
final class BrowserPageSession: Identifiable {
    typealias ID = UUID

    let id: ID
    let pageTurnID: BrowserTurn.ID
    let isIncognito: Bool
    var title: String
    var urlString: String
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var favicon: NSImage?
    var pageBackgroundColor: NSColor?

    @ObservationIgnored var onURLChange: ((String) -> Void)?
    @ObservationIgnored var onTitleChange: ((String) -> Void)?
    @ObservationIgnored var onFaviconURLChange: ((String) -> Void)?
    @ObservationIgnored var onBrowserClose: (() -> Void)?

    @ObservationIgnored private var loadedFaviconURL: String?
    @ObservationIgnored private var faviconFetchTask: Task<Void, Never>?
    @ObservationIgnored private let initialURL: String
    @ObservationIgnored private lazy var observer = BrowserPageSessionObserver(session: self)
    @ObservationIgnored lazy var browserController: TungstenBrowserController = {
        let controller = TungstenBrowserController(initialURL: initialURL, incognito: isIncognito)
        controller.delegate = observer
        controller.browserDidCloseHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.onBrowserClose?()
            }
        }
        return controller
    }()
}
```

Copy the existing navigation, favicon, zoom, find, close, and reset methods from `BrowserTab`, changing the type name and adding `pageTurnID` to the initializer:

```swift
init(pageTurnID: BrowserTurn.ID, initialURL: String, title: String = "New Page", isIncognito: Bool) {
    self.pageTurnID = pageTurnID
    self.initialURL = initialURL
    self.isIncognito = isIncognito
    self.urlString = initialURL
    self.title = title
}
```

- [ ] **Step 4: Create `LivePageSessionHost`**

Create `Tungsten/Tungsten/Browser/Threads/LivePageSessionHost.swift`:

```swift
import Foundation

@Observable @MainActor
final class LivePageSessionHost {
    private(set) var activePageSession: BrowserPageSession?

    func activate(
        pageTurn: BrowserTurn,
        isIncognito: Bool,
        configure: (BrowserPageSession) -> Void
    ) {
        guard pageTurn.kind == .page, let urlString = pageTurn.urlString else {
            closeActivePage()
            return
        }

        if activePageSession?.pageTurnID == pageTurn.id {
            return
        }

        closeActivePage()
        let session = BrowserPageSession(
            pageTurnID: pageTurn.id,
            initialURL: urlString,
            title: pageTurn.title.isEmpty ? "New Page" : pageTurn.title,
            isIncognito: isIncognito
        )
        configure(session)
        activePageSession = session
    }

    func closeActivePage() {
        activePageSession?.closeBrowser()
        activePageSession = nil
    }

    func closeActivePageForWindowClose() {
        activePageSession?.closeBrowserForWindowClose()
        activePageSession = nil
    }
}
```

- [ ] **Step 5: Update `BrowserModel` to compile with extracted type**

In `BrowserModel.swift`, remove the embedded `BrowserTab` and `BrowserControllerObserver` definitions after their extraction. Keep the existing tab-oriented `BrowserModel` behavior compiling in this task by using a temporary compatibility alias:

```swift
typealias BrowserTab = BrowserPageSession
```

Place the typealias near the top of `BrowserModel.swift` only for this task. Add a temporary computed bridge if needed:

```swift
var activePageSession: BrowserPageSession? {
    selectedTab
}
```

Remove the typealias and old `tabs` array in Task 5 after the full model migration.

- [ ] **Step 6: Run lifecycle test and build**

Run:

```bash
bash Tests/ThreadBrowserLifecycleTests.sh
./scripts/build-debug.sh
```

Expected: lifecycle test passes and Xcode reports `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add Tests/ThreadBrowserLifecycleTests.sh Tungsten/Tungsten/Browser/Threads/BrowserPageSession.swift Tungsten/Tungsten/Browser/Threads/LivePageSessionHost.swift Tungsten/Tungsten/Browser/BrowserModel.swift
git commit -m "refactor: extract live browser page session"
```

---

### Task 5: Migrate BrowserModel From Tabs to Threads

**Files:**
- Create: `Tungsten/Tungsten/Browser/Threads/BrowserWindowSessionCoordinator.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserWindowRoot.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserDetailView.swift`
- Modify: `Tungsten/Tungsten/TungstenApp.swift`
- Modify: `Tests/ThreadBrowserLifecycleTests.sh`

- [ ] **Step 1: Strengthen lifecycle test for no tab array**

Add these checks to `Tests/ThreadBrowserLifecycleTests.sh`:

```bash
if ! rg -q "var threads: \\[BrowserThread\\]" "$model_file"; then
    echo "BrowserModel must own browser threads." >&2
    exit 1
fi

if ! rg -q "selectedThreadID" "$model_file"; then
    echo "BrowserModel must track selectedThreadID instead of selectedTabID." >&2
    exit 1
fi

if rg -q "typealias BrowserTab = BrowserPageSession" "$model_file"; then
    echo "Temporary BrowserTab typealias must be removed after thread migration." >&2
    exit 1
fi
```

- [ ] **Step 2: Run lifecycle test and verify RED**

Run:

```bash
bash Tests/ThreadBrowserLifecycleTests.sh
```

Expected: FAIL while `BrowserModel` still exposes tab state or the temporary typealias.

- [ ] **Step 3: Replace `BrowserModel` state**

In `BrowserModel.swift`, replace tab-oriented state with:

```swift
var threads: [BrowserThread] = []
var selectedThreadID: BrowserThread.ID? {
    didSet {
        guard oldValue != selectedThreadID else { return }
        if let oldValue {
            previousSelectedThreadID = oldValue
        }
        activateSelectedThreadPage()
    }
}
var addressText: String = ""
var addressFocusRequestID = 0
var isSidebarVisible = true
var isFindBarVisible = false
var isHistoryVisible = false
var isGeneratingResponse = false
var findText = ""
var findFocusRequestID = 0

var selectedThread: BrowserThread? {
    threads.first { $0.id == selectedThreadID }
}

var activePageSession: BrowserPageSession? {
    livePageHost.activePageSession
}

private var previousSelectedThreadID: BrowserThread.ID?
private let threadStore: BrowserThreadStore
private let livePageHost = LivePageSessionHost()
private let aiResponseCoordinator: AIResponseCoordinator
private var responseTask: Task<Void, Never>?
private var pendingWindowCloseSessionID: BrowserPageSession.ID?
private var didCloseBrowsersForWindowClose = false
private var windowCloseCompletion: (() -> Void)?
```

Update the initializer signature:

```swift
init(
    kind: BrowserWindowKind = .normal,
    historyStore: HistoryStore = HistoryStore(),
    appPreferences: AppPreferences = AppPreferences(),
    threadStore: BrowserThreadStore? = nil,
    localAI: LocalAIAnswering? = nil
) {
    self.kind = kind
    self.historyStore = historyStore
    self.appPreferences = appPreferences
    self.threadStore = threadStore ?? BrowserThreadStore(scope: kind.isIncognito ? .memoryOnly : .persistent(windowSessionID: BrowserThreadStore.makeWindowSessionID()))
    let resolvedLocalAI = localAI ?? ProviderBackedLocalAIResponder(provider: { appPreferences.localAIProvider })
    self.aiResponseCoordinator = AIResponseCoordinator(localAI: resolvedLocalAI, searchEngine: appPreferences.searchEngine)

    let snapshot = self.threadStore.load()
    self.threads = snapshot.threads
    self.selectedThreadID = snapshot.selectedThreadID

    if threads.isEmpty {
        createThread()
    } else {
        activateSelectedThreadPage()
    }
}
```

- [ ] **Step 4: Add thread actions**

Replace `addTab`, `closeSelectedTab`, tab selection, and reopen methods with:

```swift
func createThread() {
    let thread = BrowserThread()
    threads.append(thread)
    selectedThreadID = thread.id
    persistThreads()
}

func closeSelectedThread() {
    guard let selectedThreadID, let index = threads.firstIndex(where: { $0.id == selectedThreadID }) else {
        return
    }

    threads.remove(at: index)
    if threads.isEmpty {
        createThread()
        return
    }

    self.selectedThreadID = threads[min(index, threads.count - 1)].id
    persistThreads()
}

func selectThread(atZeroBasedIndex index: Int) {
    guard threads.indices.contains(index) else {
        return
    }
    selectedThreadID = threads[index].id
}

func selectPreviousThread() {
    guard
        let selectedThreadID,
        let index = threads.firstIndex(where: { $0.id == selectedThreadID }),
        index > threads.startIndex
    else {
        return
    }

    self.selectedThreadID = threads[index - 1].id
}

func selectNextThread() {
    guard
        let selectedThreadID,
        let index = threads.firstIndex(where: { $0.id == selectedThreadID }),
        index < threads.index(before: threads.endIndex)
    else {
        return
    }

    self.selectedThreadID = threads[index + 1].id
}

func selectRecentThread() {
    guard
        let previousSelectedThreadID,
        threads.contains(where: { $0.id == previousSelectedThreadID })
    else {
        return
    }

    selectedThreadID = previousSelectedThreadID
}
```

Add these shared helpers:

```swift
private func ensureSelectedThread() {
    if let selectedThreadID, threads.contains(where: { $0.id == selectedThreadID }) {
        return
    }

    let thread = BrowserThread()
    threads.append(thread)
    selectedThreadID = thread.id
}

private func persistThreads() {
    threadStore.save(threads: threads, selectedThreadID: selectedThreadID)
}
```

Keep compatibility wrappers only where shortcuts still call old names during this task:

```swift
func addTab(navigateTo urlString: String? = nil) {
    createThread()
    if let urlString {
        appendPageTurn(urlString)
    }
}

func closeSelectedTab() {
    closeSelectedThread()
}
```

Remove those wrappers in Task 7 after shortcut migration.

- [ ] **Step 5: Route submitted input**

Replace `submitAddressBar()` with:

```swift
func submitAddressBar() {
    guard let submission = BrowserInputClassifier.submission(for: addressText, searchEngine: appPreferences.searchEngine) else {
        return
    }

    let submittedText = addressText
    addressText = ""

    switch submission {
    case .page(let urlString):
        appendPageTurn(urlString)
    case .question(let question):
        appendQuestionTurn(question.isEmpty ? submittedText : question)
    }
}
```

Add:

```swift
private func appendPageTurn(_ urlString: String) {
    ensureSelectedThread()
    guard let selectedThreadID, let index = threads.firstIndex(where: { $0.id == selectedThreadID }) else {
        return
    }

    let turnID = threads[index].appendPage(urlString: urlString)
    persistThreads()
    activatePageTurn(turnID, in: threads[index].id)
}

private func appendQuestionTurn(_ question: String) {
    ensureSelectedThread()
    guard let selectedThreadID, let index = threads.firstIndex(where: { $0.id == selectedThreadID }) else {
        return
    }

    threads[index].appendQuestion(question)
    persistThreads()
    isGeneratingResponse = true
    responseTask?.cancel()
    responseTask = Task { [weak self, question] in
        guard let self else { return }
        let result = await aiResponseCoordinator.response(for: question)
        await MainActor.run {
            self.finishAIResponse(result, for: selectedThreadID)
        }
    }
}

private func finishAIResponse(_ result: AIResponseResult, for threadID: BrowserThread.ID) {
    isGeneratingResponse = false
    guard let index = threads.firstIndex(where: { $0.id == threadID }) else {
        return
    }

    switch result {
    case .assistant(let text):
        threads[index].appendAssistantResponse(text)
    case .fallbackPage(let systemMessage, let urlString):
        threads[index].appendSystemMessage(systemMessage)
        let pageTurnID = threads[index].appendPage(urlString: urlString, title: "AI Search")
        activatePageTurn(pageTurnID, in: threadID)
    }

    persistThreads()
}
```

- [ ] **Step 6: Wire live page activation and history callbacks**

Add:

```swift
private func activateSelectedThreadPage() {
    guard let thread = selectedThread, let pageTurn = thread.activePageTurn else {
        livePageHost.closeActivePage()
        return
    }

    livePageHost.activate(pageTurn: pageTurn, isIncognito: kind.isIncognito) { [weak self] session in
        self?.configurePageCallbacks(for: session)
    }
}

private func activatePageTurn(_ turnID: BrowserTurn.ID, in threadID: BrowserThread.ID) {
    guard let index = threads.firstIndex(where: { $0.id == threadID }) else {
        return
    }

    threads[index].activatePageTurn(turnID)
    if selectedThreadID != threadID {
        selectedThreadID = threadID
    } else {
        activateSelectedThreadPage()
    }
    persistThreads()
}

private func configurePageCallbacks(for session: BrowserPageSession) {
    session.onURLChange = { [weak self, weak session] urlString in
        guard let self, let session else { return }
        self.recordPageURL(urlString, session: session)
    }

    session.onTitleChange = { [weak self, weak session] title in
        guard let self, let session else { return }
        self.recordPageTitle(title, session: session)
    }

    session.onFaviconURLChange = { [weak self, weak session] faviconURLString in
        guard let self, let session else { return }
        self.recordPageFavicon(faviconURLString, session: session)
    }
}
```

Replace old history methods with `recordPageURL`, `recordPageTitle`, and `recordPageFavicon` that update the matching `BrowserThread` page metadata by `session.pageTurnID`, call `historyStore.recordVisit` or `updateTitle` for normal windows, and then call `persistThreads()`.

Use this implementation:

```swift
private func recordPageURL(_ urlString: String, session: BrowserPageSession) {
    updatePageTurn(session: session, urlString: urlString)

    guard kind == .normal else {
        return
    }

    historyStore.recordVisit(urlString: urlString, title: session.displayTitle)
}

private func recordPageTitle(_ title: String, session: BrowserPageSession) {
    updatePageTurn(session: session, title: title)

    guard kind == .normal else {
        return
    }

    historyStore.updateTitle(for: session.urlString, title: title)
}

private func recordPageFavicon(_ faviconURLString: String, session: BrowserPageSession) {
    updatePageTurn(session: session, faviconURLString: faviconURLString)
}

private func updatePageTurn(
    session: BrowserPageSession,
    urlString: String? = nil,
    title: String? = nil,
    faviconURLString: String? = nil
) {
    guard let threadIndex = threads.firstIndex(where: { thread in
        thread.turns.contains { $0.id == session.pageTurnID }
    }) else {
        return
    }

    threads[threadIndex].updatePageMetadata(
        turnID: session.pageTurnID,
        urlString: urlString,
        title: title,
        faviconURLString: faviconURLString
    )
    persistThreads()
}

func activatePageTurnInSelectedThread(_ turnID: BrowserTurn.ID) {
    guard let selectedThreadID else {
        return
    }

    activatePageTurn(turnID, in: selectedThreadID)
}
```

- [ ] **Step 7: Update window close and page commands**

Change close cleanup:

```swift
func closeBrowsersForWindowClose(completion: @escaping () -> Void) {
    guard didCloseBrowsersForWindowClose == false else {
        if windowCloseCompletion == nil {
            completion()
        }
        return
    }

    didCloseBrowsersForWindowClose = true
    isFindBarVisible = false
    isHistoryVisible = false
    findText = ""
    windowCloseCompletion = completion

    guard let activePageSession else {
        finishWindowCloseIfNeeded()
        return
    }

    let pageSessionID = activePageSession.id
    pendingWindowCloseSessionID = pageSessionID
    activePageSession.onBrowserClose = { [weak self] in
        self?.markWindowCloseBrowserClosed(pageSessionID)
    }
    activePageSession.closeBrowserForWindowClose()

    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        self?.finishWindowCloseIfNeeded()
    }
}
```

Update back/forward/reload/stop/zoom/find/copy URL methods to use `activePageSession`.

Use these window-close helpers:

```swift
private func markWindowCloseBrowserClosed(_ sessionID: BrowserPageSession.ID) {
    guard pendingWindowCloseSessionID == sessionID else {
        return
    }

    pendingWindowCloseSessionID = nil
    activePageSession?.onBrowserClose = nil
    finishWindowCloseIfNeeded()
}

private func finishWindowCloseIfNeeded() {
    guard let completion = windowCloseCompletion else {
        return
    }

    pendingWindowCloseSessionID = nil
    windowCloseCompletion = nil
    completion()
}
```

- [ ] **Step 8: Create normal-window session coordinator**

Create `Tungsten/Tungsten/Browser/Threads/BrowserWindowSessionCoordinator.swift`:

```swift
import Foundation

@Observable @MainActor
final class BrowserWindowSessionCoordinator {
    private var didClaimInitialNormalWindow = false

    func makeThreadStore(kind: BrowserWindowKind) -> BrowserThreadStore {
        if kind.isIncognito {
            return BrowserThreadStore(scope: .memoryOnly)
        }

        if didClaimInitialNormalWindow == false {
            didClaimInitialNormalWindow = true
            let sessionID = BrowserThreadStore.mostRecentWindowSessionID() ?? BrowserThreadStore.makeWindowSessionID()
            BrowserThreadStore.markWindowSessionActive(sessionID)
            return BrowserThreadStore(scope: .persistent(windowSessionID: sessionID))
        }

        let sessionID = BrowserThreadStore.makeWindowSessionID()
        BrowserThreadStore.markWindowSessionActive(sessionID)
        return BrowserThreadStore(scope: .persistent(windowSessionID: sessionID))
    }
}
```

This preserves the single-window cold-launch behavior while making each additional new normal window start with its own separate thread store.

- [ ] **Step 9: Pass the coordinator from `TungstenApp`**

In `TungstenApp`, add:

```swift
@State private var windowSessionCoordinator = BrowserWindowSessionCoordinator()
```

Pass it to both normal and incognito roots:

```swift
BrowserWindowRoot(
    kind: .normal,
    shortcutManager: shortcutManager,
    historyStore: historyStore,
    appPreferences: appPreferences,
    windowSessionCoordinator: windowSessionCoordinator
)
```

and:

```swift
BrowserWindowRoot(
    kind: .incognito,
    shortcutManager: shortcutManager,
    historyStore: historyStore,
    appPreferences: appPreferences,
    windowSessionCoordinator: windowSessionCoordinator
)
```

- [ ] **Step 10: Update `BrowserWindowRoot` store creation**

Add a `windowSessionCoordinator` parameter and pass a store into `BrowserModel`:

```swift
let windowSessionCoordinator: BrowserWindowSessionCoordinator
```

Use this when initializing `BrowserModel`:

```swift
_browserModel = State(initialValue: BrowserModel(
    kind: kind,
    historyStore: historyStore,
    appPreferences: appPreferences,
    threadStore: windowSessionCoordinator.makeThreadStore(kind: kind)
))
```

- [ ] **Step 11: Update `BrowserDetailView`**

Change the property:

```swift
let pageSession: BrowserPageSession
```

And update the `BrowserView` initializer call:

```swift
BrowserView(controller: pageSession.browserController)
    .id(pageSession.pageTurnID)
```

- [ ] **Step 12: Run tests and build**

Run:

```bash
swiftc \
  Tungsten/Tungsten/Browser/SearchEngine.swift \
  Tungsten/Tungsten/Browser/AddressResolver.swift \
  Tungsten/Tungsten/Browser/Threads/*.swift \
  Tests/ThreadModelTests.swift \
  -o /tmp/TungstenThreadModelTests && /tmp/TungstenThreadModelTests
bash Tests/ThreadBrowserLifecycleTests.sh
./scripts/build-debug.sh
```

Expected: thread model tests and lifecycle structural tests pass; Xcode reports `BUILD SUCCEEDED`.

- [ ] **Step 13: Commit**

```bash
git add Tungsten/Tungsten/Browser/Threads/BrowserWindowSessionCoordinator.swift Tungsten/Tungsten/Browser/BrowserModel.swift Tungsten/Tungsten/Browser/BrowserWindowRoot.swift Tungsten/Tungsten/Browser/BrowserDetailView.swift Tungsten/Tungsten/TungstenApp.swift Tests/ThreadBrowserLifecycleTests.sh
git commit -m "feat: migrate browser model to threads"
```

---

### Task 6: Replace Sidebar Tab List With Thread Timeline

**Files:**
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift`

- [ ] **Step 1: Replace sidebar list structure**

Replace `BrowserSidebar` with three regions:

```swift
VStack(spacing: 0) {
    ThreadHeader(
        threads: browserModel.threads,
        selectedThreadID: $browserModel.selectedThreadID,
        onNewThread: { browserModel.createThread() },
        onCloseThread: { browserModel.closeSelectedThread() }
    )

    Divider()

    ThreadTimeline(
        thread: browserModel.selectedThread,
        activePageTurnID: browserModel.selectedThread?.activePageTurnID,
        isGeneratingResponse: browserModel.isGeneratingResponse,
        onActivatePage: { turnID in browserModel.activatePageTurnInSelectedThread(turnID) }
    )

    Divider()

    ChatInput(
        text: $browserModel.addressText,
        focusRequestID: browserModel.addressFocusRequestID,
        onSubmit: { browserModel.submitAddressBar() }
    )
}
```

Add a public `BrowserModel.activatePageTurnInSelectedThread(_:)` method that calls the private activation helper for the selected thread.

- [ ] **Step 2: Add thread header**

Create a private `ThreadHeader` view in `BrowserSplitView.swift`:

```swift
private struct ThreadHeader: View {
    let threads: [BrowserThread]
    @Binding var selectedThreadID: BrowserThread.ID?
    let onNewThread: () -> Void
    let onCloseThread: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Thread", selection: $selectedThreadID) {
                ForEach(threads) { thread in
                    Text(thread.displayTitle).tag(Optional(thread.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button("New Thread", systemImage: "plus") {
                onNewThread()
            }
            .help("New Thread")

            Button("Close Thread", systemImage: "xmark") {
                onCloseThread()
            }
            .disabled(threads.isEmpty)
            .help("Close Thread")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
```

- [ ] **Step 3: Add thread timeline and bubbles**

Create private `ThreadTimeline`, `ThreadTurnBubble`, and `PendingAssistantBubble` views. Use a `ScrollViewReader` so new turns scroll into view:

```swift
private struct ThreadTimeline: View {
    let thread: BrowserThread?
    let activePageTurnID: BrowserTurn.ID?
    let isGeneratingResponse: Bool
    let onActivatePage: (BrowserTurn.ID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let thread {
                        ForEach(thread.turns) { turn in
                            ThreadTurnBubble(
                                turn: turn,
                                isActivePage: turn.id == activePageTurnID,
                                onActivatePage: { onActivatePage(turn.id) }
                            )
                            .id(turn.id)
                        }
                    }

                    if isGeneratingResponse {
                        PendingAssistantBubble()
                            .id("pending-assistant")
                    }
                }
                .padding(12)
            }
            .onChange(of: thread?.turns.count ?? 0) { _, _ in
                scrollToBottom(thread: thread, proxy: proxy)
            }
            .onChange(of: isGeneratingResponse) { _, _ in
                scrollToBottom(thread: thread, proxy: proxy)
            }
        }
    }

    private func scrollToBottom(thread: BrowserThread?, proxy: ScrollViewProxy) {
        withAnimation(.smooth(duration: 0.18)) {
            if isGeneratingResponse {
                proxy.scrollTo("pending-assistant", anchor: .bottom)
            } else if let lastID = thread?.turns.last?.id {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}
```

`ThreadTurnBubble` should:

- Align user questions to trailing.
- Align assistant/system bubbles to leading.
- Render page turns as full-width compact rows with favicon/globe, title, URL, and active ring.
- Use `Button` for page turns so older URL turns can be reactivated.

- [ ] **Step 4: Add rainbow response animation with Reduce Motion**

Add:

```swift
private struct PendingAssistantBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(rainbowStyle, lineWidth: 1.5)
        }
        .onAppear {
            guard reduceMotion == false else { return }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                phase = true
            }
        }
    }

    private var rainbowStyle: LinearGradient {
        LinearGradient(
            colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
            startPoint: phase && reduceMotion == false ? .topTrailing : .topLeading,
            endPoint: phase && reduceMotion == false ? .bottomLeading : .bottomTrailing
        )
    }
}
```

Keep bubble corner radii at `8` or less unless the existing input container requires a larger radius.

- [ ] **Step 5: Update detail column binding**

In `BrowserSplitView`, replace `let tab = browserModel.selectedTab` with:

```swift
let pageSession = browserModel.activePageSession
```

Render:

```swift
if let pageSession {
    ZStack(alignment: .topTrailing) {
        BrowserDetailView(pageSession: pageSession)
        ...
    }
} else {
    ContentUnavailableView("No Page", systemImage: "text.bubble")
}
```

- [ ] **Step 6: Build**

Run:

```bash
./scripts/build-debug.sh
```

Expected: Xcode reports `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add Tungsten/Tungsten/Browser/BrowserSplitView.swift
git commit -m "feat: render browser threads in sidebar"
```

---

### Task 7: Update Shortcuts From Tabs to Threads

**Files:**
- Modify: `Tests/ShortcutLogicTests.swift`
- Modify: `Tungsten/Tungsten/Shortcuts/Core/ShortcutAction.swift`
- Modify: `Tungsten/Tungsten/Shortcuts/ShortcutDispatcher.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`

- [ ] **Step 1: Update shortcut tests**

In `Tests/ShortcutLogicTests.swift`, replace user-facing tab labels with thread labels:

```swift
try expect(ShortcutCatalog.action(id: .newTab)?.title == "New Thread")
try expect(ShortcutCatalog.action(id: .closeCurrentTab)?.title == "Close Current Thread")
try expect(ShortcutCatalog.action(id: .focusAddressInput)?.title == "Ask or Open URL")
try expect(ShortcutCatalog.action(id: .selectTab1)?.title == "Go to Thread 1")
try expect(ShortcutCatalog.action(id: .selectPreviousTab)?.title == "Previous Thread")
try expect(ShortcutCatalog.action(id: .selectNextTab)?.title == "Next Thread")
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected: FAIL because labels still say Tab.

- [ ] **Step 3: Update catalog labels**

In `ShortcutAction.swift`, change titles:

```swift
available(.newTab, "New Thread", .everyday, [.cmd("t")])
available(.closeCurrentTab, "Close Current Thread", .everyday, [.cmd("w")])
available(.reopenLastClosedTab, "Re-open Last Closed Thread", .everyday, [.cmdShift("t")])
available(.pinOrUnpinCurrentTab, "Pin or Unpin Current Thread", .everyday, [.cmd("d")])
available(.focusAddressInput, "Ask or Open URL", .everyday, [.cmd("l")])
available(.clearUnpinnedTabs, "Clear Unpinned Threads", .everyday, [.cmdShift("k")])
available(.selectTab1, "Go to Thread 1", .quickNavigation, [.cmd("1")])
available(.selectTab2, "Go to Thread 2", .quickNavigation, [.cmd("2")])
available(.selectTab3, "Go to Thread 3", .quickNavigation, [.cmd("3")])
available(.selectTab4, "Go to Thread 4", .quickNavigation, [.cmd("4")])
available(.selectTab5, "Go to Thread 5", .quickNavigation, [.cmd("5")])
available(.selectTab6, "Go to Thread 6", .quickNavigation, [.cmd("6")])
available(.selectTab7, "Go to Thread 7", .quickNavigation, [.cmd("7")])
available(.selectTab8, "Go to Thread 8", .quickNavigation, [.cmd("8")])
available(.selectTab9, "Go to Thread 9", .quickNavigation, [.cmd("9")])
available(.selectRecentTab, "Toggle Recent Threads", .quickNavigation, [.control(ShortcutBinding.tabKey)])
available(.selectPreviousTab, "Previous Thread", .quickNavigation, [.cmdOption(ShortcutBinding.upArrowKey)])
available(.selectNextTab, "Next Thread", .quickNavigation, [.cmdOption(ShortcutBinding.downArrowKey)])
```

- [ ] **Step 4: Update dispatcher**

Change dispatcher calls:

```swift
case .newTab:
    browserModel.createThread()
case .closeCurrentTab:
    browserModel.closeSelectedThread()
case .reopenLastClosedTab:
    browserModel.reopenLastClosedThread()
case .pinOrUnpinCurrentTab:
    browserModel.toggleSelectedThreadPin()
case .clearUnpinnedTabs:
    browserModel.clearUnpinnedThreads()
case .selectTab1:
    browserModel.selectThread(atZeroBasedIndex: 0)
...
case .selectRecentTab:
    browserModel.selectRecentThread()
case .selectPreviousTab:
    browserModel.selectPreviousThread()
case .selectNextTab:
    browserModel.selectNextThread()
case .goBack:
    browserModel.activePageSession?.goBack()
case .goForward:
    browserModel.activePageSession?.goForward()
case .reloadOrStopLoading:
    if browserModel.activePageSession?.isLoading == true {
        browserModel.activePageSession?.stopLoading()
    } else {
        browserModel.activePageSession?.reload()
    }
```

Implement `BrowserModel.reopenLastClosedThread`, `toggleSelectedThreadPin`, and `clearUnpinnedThreads` using thread metadata. Store closed thread snapshots in memory for normal windows:

```swift
private var closedThreads: [BrowserThread] = []
```

Add these methods to `BrowserModel`:

```swift
func reopenLastClosedThread() {
    guard kind == .normal, let thread = closedThreads.popLast() else {
        return
    }

    threads.append(thread)
    selectedThreadID = thread.id
    persistThreads()
}

func toggleSelectedThreadPin() {
    guard let selectedThreadID, let index = threads.firstIndex(where: { $0.id == selectedThreadID }) else {
        return
    }

    threads[index].isPinned.toggle()
    persistThreads()
}

func clearUnpinnedThreads() {
    let pinnedThreads = threads.filter(\.isPinned)
    guard pinnedThreads.count != threads.count else {
        return
    }

    threads = pinnedThreads
    if threads.isEmpty {
        createThread()
        return
    }

    if let selectedThreadID, threads.contains(where: { $0.id == selectedThreadID }) {
        persistThreads()
    } else {
        selectedThreadID = threads.first?.id
        persistThreads()
    }
}
```

In `closeSelectedThread()`, append normal-window closed snapshots before removal:

```swift
if kind == .normal {
    closedThreads.append(threads[index])
}
```

- [ ] **Step 5: Remove compatibility wrappers**

Remove `addTab`, `closeSelectedTab`, `selectedTab`, and `BrowserTab` compatibility wrappers from `BrowserModel.swift`. Keep page command methods named `zoomIn`, `zoomOut`, `resetZoom`, and find methods because UI and dispatcher use those as page-level operations.

- [ ] **Step 6: Run shortcut tests and build**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
./scripts/build-debug.sh
```

Expected: shortcut tests pass and Xcode reports `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add Tests/ShortcutLogicTests.swift Tungsten/Tungsten/Shortcuts/Core/ShortcutAction.swift Tungsten/Tungsten/Shortcuts/ShortcutDispatcher.swift Tungsten/Tungsten/Browser/BrowserModel.swift
git commit -m "feat: update shortcuts for threads"
```

---

### Task 8: Final Verification and Manual Smoke

**Files:**
- Modify only if verification exposes a defect in files changed by Tasks 1-7.

- [ ] **Step 1: Run model and AI tests**

Run:

```bash
swiftc \
  Tungsten/Tungsten/Browser/SearchEngine.swift \
  Tungsten/Tungsten/Browser/AddressResolver.swift \
  Tungsten/Tungsten/Browser/Threads/*.swift \
  Tests/ThreadModelTests.swift \
  -o /tmp/TungstenThreadModelTests && /tmp/TungstenThreadModelTests
swiftc \
  Tungsten/Tungsten/Browser/SearchEngine.swift \
  Tungsten/Tungsten/Browser/AddressResolver.swift \
  Tungsten/Tungsten/Browser/Threads/*.swift \
  Tungsten/Tungsten/Browser/AI/*.swift \
  Tests/AIResponseCoordinatorTests.swift \
  -o /tmp/TungstenAIResponseCoordinatorTests && /tmp/TungstenAIResponseCoordinatorTests
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected:

```text
ThreadModelTests passed
AIResponseCoordinatorTests passed
ShortcutLogicTests passed
```

- [ ] **Step 2: Run structural shell tests**

Run:

```bash
bash Tests/ThreadBrowserLifecycleTests.sh
bash Tests/BrowserModelClosePolicyTests.sh
bash Tests/LocalAISettingsTests.sh
bash Tests/CEFBrowserLifecycleTests.sh
```

Expected:

```text
ThreadBrowserLifecycleTests passed
BrowserModelClosePolicyTests passed
LocalAISettingsTests passed
CEFBrowserLifecycleTests passed
```

If `BrowserModelClosePolicyTests.sh` still asserts tab-specific wording after the migration, update it to assert that closing the only thread creates or keeps a replacement thread and does not tear down CEF before window close. Do not delete the test.

- [ ] **Step 3: Run Xcode build**

Run:

```bash
./scripts/build-debug.sh
```

Expected: Xcode reports `BUILD SUCCEEDED`.

- [ ] **Step 4: Manual smoke test**

Launch the debug app from the build output:

```bash
open /tmp/TungstenDerivedData/Build/Products/Debug/Tungsten.app
```

Verify:

- Submitting `https://example.com` creates a page bubble and renders the page.
- Submitting `what is tungsten` creates a question bubble, shows the rainbow pending response state, then appends a response or AI-search fallback page.
- Reopening the older `https://example.com` page bubble reloads it and leaves only one page visible in the detail pane.
- Creating more than one thread shows them in the thread picker.
- `Command-T` creates a thread.
- `Command-W` closes the current thread without closing the app window.
- Turning on macOS Reduce Motion replaces the animated rainbow shimmer with a static accent or standard progress state.

- [ ] **Step 5: Commit verification fixes if needed**

If Step 1-4 required code fixes:

```bash
git add Tests/ThreadModelTests.swift Tests/AIResponseCoordinatorTests.swift Tests/ThreadBrowserLifecycleTests.sh Tests/BrowserModelClosePolicyTests.sh Tests/ShortcutLogicTests.swift Tungsten/Tungsten/Browser Tungsten/Tungsten/Shortcuts Tungsten/Tungsten/AppPreferences.swift Tungsten/Tungsten/TungstenApp.swift
git commit -m "fix: stabilize thread browser verification"
```

If no fixes were needed, do not create an empty commit.
