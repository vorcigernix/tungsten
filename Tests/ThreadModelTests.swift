import Foundation

@main
struct ThreadModelTests {
    @MainActor
    static func main() throws {
        try testBlankTabStartsWithoutURL()
        try testDirectURLInputClassifiesAsPage()
        try testBareDomainInputClassifiesAsPage()
        try testLocalhostInputClassifiesAsPage()
        try testSearchKeywordClassifiesAsSearchPage()
        try testNaturalLanguageInputClassifiesAsQuestion()
        try testSearchEngineDefaultsUseDuckDuckGo()
        try testAddressBarAIProviderURLs()
        try testTorPreferencesDefaultToArtiLaunch()
        try testTabMetadataUpdates()
        try testBrowserTabPrivacyModeDefaultsToNormal()
        try testBrowserTabCodableRoundTrip()
        try testPersistentStoreDoesNotSavePrivateOrTorTabs()
        try testPersistentStoreCapsTabs()
        try testPersistentStorePreservesSelectedTabWhenCapping()
        try testPersistentStoreSanitizesOversizedTabsOnSave()
        try testPersistentStoreSanitizesOversizedTabsOnLoad()
        try testMemoryOnlyStoreDoesNotWriteDefaults()
        try testOldThreadKeysAreIgnoredAndPreserved()
        try testMostRecentWindowSessionIsTracked()
        try testWindowSessionCoordinatorRestoresAgainAfterLastNormalWindowCloses()
        print("ThreadModelTests passed")
    }

    static func testBlankTabStartsWithoutURL() throws {
        let tab = BrowserTab()

        try expect(tab.urlString == nil)
        try expect(tab.displayTitle == "Untitled")
        try expect(tab.displaySubtitle == "New Tab")
    }

    static func testDirectURLInputClassifiesAsPage() throws {
        try expect(BrowserInputClassifier.submission(
            for: "https://example.com/docs",
            searchEngine: .duckDuckGo
        ) == .page(urlString: "https://example.com/docs"))
    }

    static func testBareDomainInputClassifiesAsPage() throws {
        try expect(BrowserInputClassifier.submission(
            for: "example.com/path",
            searchEngine: .duckDuckGo
        ) == .page(urlString: "https://example.com/path"))
    }

    static func testLocalhostInputClassifiesAsPage() throws {
        try expect(BrowserInputClassifier.submission(
            for: "localhost:3000",
            searchEngine: .duckDuckGo
        ) == .page(urlString: "http://localhost:3000"))
    }

    static func testSearchKeywordClassifiesAsSearchPage() throws {
        try expect(BrowserInputClassifier.submission(
            for: "search tungsten carbide",
            searchEngine: .google
        ) == .page(urlString: "https://www.google.com/search?q=tungsten%20carbide"))
    }

    static func testNaturalLanguageInputClassifiesAsQuestion() throws {
        try expect(BrowserInputClassifier.submission(
            for: "what is tungsten carbide",
            searchEngine: .duckDuckGo
        ) == .question("what is tungsten carbide"))
    }

    static func testSearchEngineDefaultsUseDuckDuckGo() throws {
        try expect(SearchEngine.duckDuckGo.homepageURL == "https://duckduckgo.com")
        try expect(SearchEngine.duckDuckGo.searchURL(for: "hello world") == "https://duckduckgo.com/?q=hello%20world")
    }

    static func testAddressBarAIProviderURLs() throws {
        try expect(AddressBarAIProvider.duckDuckGoAI.responseURL(for: "what is tungsten carbide") == "https://duck.ai/chat?prompt=1&home=1&q=what%20is%20tungsten%20carbide")
        try expect(AddressBarAIProvider.googleAI.responseURL(for: "what is tungsten carbide") == "https://www.google.com/search?udm=50&q=what%20is%20tungsten%20carbide")
    }

    @MainActor
    static func testTorPreferencesDefaultToArtiLaunch() throws {
        let preferences = AppPreferences(userDefaults: makeIsolatedUserDefaults())

        try expect(preferences.torConfiguration.launchesArti)
        try expect(preferences.torConfiguration.artiExecutablePath == "arti")
        try expect(preferences.torConfiguration.socksHost == "127.0.0.1")
        try expect(preferences.torConfiguration.socksPort == 9150)
    }

    static func testTabMetadataUpdates() throws {
        var tab = BrowserTab(createdAt: Date(timeIntervalSince1970: 10))
        let updateDate = Date(timeIntervalSince1970: 50)

        tab.update(
            urlString: "https://example.com/new",
            title: "New",
            faviconURLString: "https://example.com/favicon.ico",
            updatedAt: updateDate
        )

        try expect(tab.urlString == "https://example.com/new")
        try expect(tab.title == "New")
        try expect(tab.faviconURLString == "https://example.com/favicon.ico")
        try expect(tab.displayTitle == "New")
        try expect(tab.updatedAt == updateDate)
    }

    static func testBrowserTabPrivacyModeDefaultsToNormal() throws {
        let tab = BrowserTab()

        try expect(tab.privacyMode == .normal)
        try expect(tab.isEphemeral == false)
    }

    static func testBrowserTabCodableRoundTrip() throws {
        let tab = BrowserTab(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            urlString: "https://example.com/docs",
            title: "Docs",
            faviconURLString: "https://example.com/favicon.ico",
            isPinned: true,
            privacyMode: .tor
        )

        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: data)

        try expect(decoded == tab)
        try expect(decoded.privacyMode == .tor)
    }

    static func testPersistentStoreCapsTabs() throws {
        let userDefaults = makeIsolatedUserDefaults()
        let store = BrowserTabStore(
            userDefaults: userDefaults,
            scope: .persistent(windowSessionID: "window-a")
        )
        let tabs = makeTabs(count: 61)
        let selectedTabID = tabs[60].id

        store.save(tabs: tabs, selectedTabID: selectedTabID)

        let loaded = store.load()
        try expect(loaded.tabs.count == 60)
        try expect(loaded.tabs.first?.title == "Tab 1")
        try expect(loaded.tabs.last?.title == "Tab 60")
        try expect(loaded.selectedTabID == selectedTabID)
    }

    static func testPersistentStorePreservesSelectedTabWhenCapping() throws {
        let userDefaults = makeIsolatedUserDefaults()
        let store = BrowserTabStore(
            userDefaults: userDefaults,
            scope: .persistent(windowSessionID: "window-a")
        )
        let tabs = makeTabs(count: 61)
        let selectedTabID = tabs[0].id

        store.save(tabs: tabs, selectedTabID: selectedTabID)

        let loaded = store.load()
        try expect(loaded.tabs.count == 60)
        try expect(loaded.tabs.contains { $0.id == selectedTabID })
        try expect(loaded.selectedTabID == selectedTabID)
    }

    static func testPersistentStoreDoesNotSavePrivateOrTorTabs() throws {
        let userDefaults = makeIsolatedUserDefaults()
        let store = BrowserTabStore(
            userDefaults: userDefaults,
            scope: .persistent(windowSessionID: "window-a")
        )
        let normalTab = BrowserTab(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            urlString: "https://example.com",
            title: "Normal"
        )
        let incognitoTab = BrowserTab(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            urlString: "https://private.example",
            title: "Private",
            privacyMode: .incognito
        )
        let torTab = BrowserTab(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            urlString: "https://check.torproject.org",
            title: "Tor",
            privacyMode: .tor
        )

        store.save(tabs: [normalTab, incognitoTab, torTab], selectedTabID: torTab.id)

        let loaded = store.load()
        try expect(loaded.tabs == [normalTab])
        try expect(loaded.selectedTabID == normalTab.id)
    }

    static func testPersistentStoreSanitizesOversizedTabsOnSave() throws {
        let userDefaults = makeIsolatedUserDefaults()
        let store = BrowserTabStore(
            userDefaults: userDefaults,
            scope: .persistent(windowSessionID: "window-a")
        )
        let hugeText = String(repeating: "x", count: 20_000)
        let tab = BrowserTab(urlString: "https://example.com", title: hugeText)

        store.save(tabs: [tab], selectedTabID: tab.id)

        let loaded = store.load()
        try expect(loaded.tabs.first?.title?.count == 4_000)
    }

    static func testPersistentStoreSanitizesOversizedTabsOnLoad() throws {
        let userDefaults = makeIsolatedUserDefaults()
        let store = BrowserTabStore(
            userDefaults: userDefaults,
            scope: .persistent(windowSessionID: "window-a")
        )
        let hugeText = String(repeating: "x", count: 20_000)
        let tab = BrowserTab(urlString: "https://example.com", title: hugeText)
        let snapshot = BrowserTabSnapshot(tabs: [tab], selectedTabID: tab.id)
        let key = "Tungsten.BrowserTabs.v1.window-a"
        let oversizedData = try JSONEncoder().encode(snapshot)
        userDefaults.set(oversizedData, forKey: key)

        let loaded = store.load()
        guard let sanitizedData = userDefaults.data(forKey: key) else {
            throw TestFailure(file: #filePath, line: #line)
        }

        try expect(loaded.tabs.first?.title?.count == 4_000)
        try expect(sanitizedData.count < oversizedData.count)
    }

    static func testMemoryOnlyStoreDoesNotWriteDefaults() throws {
        let userDefaults = makeIsolatedUserDefaults()
        let store = BrowserTabStore(userDefaults: userDefaults, scope: .memoryOnly)
        let tabs = makeTabs(count: 1)

        store.save(tabs: tabs, selectedTabID: tabs[0].id)

        let loaded = store.load()
        try expect(loaded.tabs.isEmpty)
        try expect(userDefaults.dictionaryRepresentation().keys.contains {
            $0.contains("Tungsten.BrowserTabs")
        } == false)
    }

    static func testOldThreadKeysAreIgnoredAndPreserved() throws {
        let userDefaults = makeIsolatedUserDefaults()
        let oldKey = "Tungsten.BrowserThreads.v1.window-a"
        let oldValue = Data([1, 2, 3, 4])
        userDefaults.set(oldValue, forKey: oldKey)

        let store = BrowserTabStore(
            userDefaults: userDefaults,
            scope: .persistent(windowSessionID: "window-a")
        )

        try expect(store.load().tabs.isEmpty)
        try expect(userDefaults.data(forKey: oldKey) == oldValue)
    }

    static func testMostRecentWindowSessionIsTracked() throws {
        let userDefaults = makeIsolatedUserDefaults()

        BrowserTabStore.markWindowSessionActive(
            "window-old",
            userDefaults: userDefaults,
            activeAt: Date(timeIntervalSince1970: 1)
        )
        BrowserTabStore.markWindowSessionActive(
            "window-new",
            userDefaults: userDefaults,
            activeAt: Date(timeIntervalSince1970: 2)
        )

        try expect(BrowserTabStore.mostRecentWindowSessionID(userDefaults: userDefaults) == "window-new")
    }

    @MainActor
    static func testWindowSessionCoordinatorRestoresAgainAfterLastNormalWindowCloses() throws {
        let userDefaults = makeIsolatedUserDefaults()
        BrowserTabStore.markWindowSessionActive(
            "restored-window",
            userDefaults: userDefaults,
            activeAt: Date(timeIntervalSince1970: 1)
        )
        let coordinator = BrowserWindowSessionCoordinator(userDefaults: userDefaults)

        let restoredStore = coordinator.makeTabStore(kind: .normal)
        try expect(restoredStore.persistentWindowSessionID == "restored-window")

        let secondStore = coordinator.makeTabStore(kind: .normal)
        try expect(secondStore.persistentWindowSessionID != "restored-window")

        coordinator.releaseTabStore(secondStore, kind: .normal)
        coordinator.releaseTabStore(restoredStore, kind: .normal)

        let reopenedStore = coordinator.makeTabStore(kind: .normal)
        try expect(reopenedStore.persistentWindowSessionID == secondStore.persistentWindowSessionID)
    }

    static func makeIsolatedUserDefaults() -> UserDefaults {
        let suiteName = "ThreadModelTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    static func makeTabs(count: Int) -> [BrowserTab] {
        (0..<count).map { index in
            BrowserTab(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                urlString: "https://example.com/\(index)",
                title: "Tab \(index)"
            )
        }
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
