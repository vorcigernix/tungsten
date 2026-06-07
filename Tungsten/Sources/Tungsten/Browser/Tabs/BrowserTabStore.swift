import Foundation

struct BrowserTabSnapshot: Codable, Equatable {
    var tabs: [BrowserTab]
    var selectedTabID: BrowserTab.ID?

    init(tabs: [BrowserTab] = [], selectedTabID: BrowserTab.ID? = nil) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
    }
}

enum BrowserTabStoreScope: Equatable {
    case persistent(windowSessionID: String)
    case memoryOnly
}

private struct BrowserTabWindowSessionRecord: Codable, Equatable {
    var id: String
    var activeAt: Date
}

final class BrowserTabStore {
    private static let maxTabs = 60
    private static let sessionIndexKey = "Tungsten.BrowserTabWindowSessions.v1"
    private static let snapshotKeyPrefix = "Tungsten.BrowserTabs.v1"

    private let userDefaults: UserDefaults
    private let scope: BrowserTabStoreScope

    var persistentWindowSessionID: String? {
        guard case let .persistent(windowSessionID) = scope else {
            return nil
        }

        return windowSessionID
    }

    init(userDefaults: UserDefaults = .standard, scope: BrowserTabStoreScope) {
        self.userDefaults = userDefaults
        self.scope = scope
    }

    func load() -> BrowserTabSnapshot {
        guard case let .persistent(windowSessionID) = scope else {
            return BrowserTabSnapshot()
        }

        let key = Self.snapshotKey(for: windowSessionID)
        guard let data = userDefaults.data(forKey: key) else {
            return BrowserTabSnapshot()
        }

        do {
            let snapshot = try JSONDecoder().decode(BrowserTabSnapshot.self, from: data)
            let sanitizedSnapshot = Self.sanitized(snapshot)
            if sanitizedSnapshot != snapshot {
                save(tabs: sanitizedSnapshot.tabs, selectedTabID: sanitizedSnapshot.selectedTabID)
            }
            return sanitizedSnapshot
        } catch {
            userDefaults.removeObject(forKey: key)
            return BrowserTabSnapshot()
        }
    }

    func save(tabs: [BrowserTab], selectedTabID: BrowserTab.ID?) {
        guard case let .persistent(windowSessionID) = scope else {
            return
        }

        let persistableTabs = tabs.filter { $0.isEphemeral == false }
        let cappedTabs = Self.capped(persistableTabs, preserving: selectedTabID)
            .map(\.sanitizedForPersistence)
        let cappedSelectedTabID: BrowserTab.ID?
        if let selectedTabID, cappedTabs.contains(where: { $0.id == selectedTabID }) {
            cappedSelectedTabID = selectedTabID
        } else {
            cappedSelectedTabID = cappedTabs.last?.id
        }

        let snapshot = BrowserTabSnapshot(
            tabs: cappedTabs,
            selectedTabID: cappedSelectedTabID
        )
        let key = Self.snapshotKey(for: windowSessionID)

        do {
            let data = try JSONEncoder().encode(snapshot)
            userDefaults.set(data, forKey: key)
            Self.markWindowSessionActive(windowSessionID, userDefaults: userDefaults)
        } catch {
            userDefaults.removeObject(forKey: key)
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

    static func markWindowSessionActive(
        _ id: String,
        userDefaults: UserDefaults = .standard,
        activeAt: Date = Date()
    ) {
        var records = sessionRecords(userDefaults: userDefaults)
        records.removeAll { $0.id == id }
        records.append(BrowserTabWindowSessionRecord(id: id, activeAt: activeAt))
        records.sort { $0.activeAt > $1.activeAt }

        do {
            let data = try JSONEncoder().encode(records)
            userDefaults.set(data, forKey: sessionIndexKey)
        } catch {
            userDefaults.removeObject(forKey: sessionIndexKey)
        }
    }

    private static func capped(
        _ tabs: [BrowserTab],
        preserving selectedTabID: BrowserTab.ID?
    ) -> [BrowserTab] {
        guard tabs.count > maxTabs else {
            return tabs
        }

        var cappedTabs = Array(tabs.suffix(maxTabs))
        guard let selectedTabID,
              cappedTabs.contains(where: { $0.id == selectedTabID }) == false,
              let selectedTab = tabs.first(where: { $0.id == selectedTabID }) else {
            return cappedTabs
        }

        cappedTabs.removeFirst()
        cappedTabs.insert(selectedTab, at: 0)
        return cappedTabs
    }

    private static func sanitized(_ snapshot: BrowserTabSnapshot) -> BrowserTabSnapshot {
        let persistableTabs = snapshot.tabs.filter { $0.isEphemeral == false }
        let tabs = capped(persistableTabs, preserving: snapshot.selectedTabID)
            .map(\.sanitizedForPersistence)
        let selectedTabID: BrowserTab.ID?
        if let snapshotSelectedTabID = snapshot.selectedTabID,
           tabs.contains(where: { $0.id == snapshotSelectedTabID }) {
            selectedTabID = snapshotSelectedTabID
        } else {
            selectedTabID = tabs.first?.id
        }

        return BrowserTabSnapshot(tabs: tabs, selectedTabID: selectedTabID)
    }

    private static func snapshotKey(for windowSessionID: String) -> String {
        "\(snapshotKeyPrefix).\(windowSessionID)"
    }

    private static func sessionRecords(userDefaults: UserDefaults) -> [BrowserTabWindowSessionRecord] {
        guard let data = userDefaults.data(forKey: sessionIndexKey) else {
            return []
        }

        return (try? JSONDecoder().decode([BrowserTabWindowSessionRecord].self, from: data)) ?? []
    }
}
