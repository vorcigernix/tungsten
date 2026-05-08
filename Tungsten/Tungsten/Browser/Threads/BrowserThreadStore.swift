import Foundation

struct BrowserThreadSnapshot: Codable, Equatable {
    var threads: [BrowserThread]
    var selectedThreadID: BrowserThread.ID?

    init(threads: [BrowserThread] = [], selectedThreadID: BrowserThread.ID? = nil) {
        self.threads = threads
        self.selectedThreadID = selectedThreadID
    }
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

    var persistentWindowSessionID: String? {
        guard case let .persistent(windowSessionID) = scope else {
            return nil
        }

        return windowSessionID
    }

    init(userDefaults: UserDefaults = .standard, scope: BrowserThreadStoreScope) {
        self.userDefaults = userDefaults
        self.scope = scope
    }

    func load() -> BrowserThreadSnapshot {
        guard case let .persistent(windowSessionID) = scope else {
            return BrowserThreadSnapshot()
        }

        let key = Self.snapshotKey(for: windowSessionID)
        guard let data = userDefaults.data(forKey: key) else {
            return BrowserThreadSnapshot()
        }

        do {
            return try JSONDecoder().decode(BrowserThreadSnapshot.self, from: data)
        } catch {
            userDefaults.removeObject(forKey: key)
            return BrowserThreadSnapshot()
        }
    }

    func save(threads: [BrowserThread], selectedThreadID: BrowserThread.ID?) {
        guard case let .persistent(windowSessionID) = scope else {
            return
        }

        let cappedThreads = Self.capped(threads, preserving: selectedThreadID)
        let cappedSelectedThreadID: BrowserThread.ID?
        if let selectedThreadID, cappedThreads.contains(where: { $0.id == selectedThreadID }) {
            cappedSelectedThreadID = selectedThreadID
        } else {
            cappedSelectedThreadID = cappedThreads.last?.id
        }

        let snapshot = BrowserThreadSnapshot(
            threads: cappedThreads,
            selectedThreadID: cappedSelectedThreadID
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
        records.append(BrowserWindowSessionRecord(id: id, activeAt: activeAt))
        records.sort { $0.activeAt > $1.activeAt }

        do {
            let data = try JSONEncoder().encode(records)
            userDefaults.set(data, forKey: sessionIndexKey)
        } catch {
            userDefaults.removeObject(forKey: sessionIndexKey)
        }
    }

    private static func capped(
        _ threads: [BrowserThread],
        preserving selectedThreadID: BrowserThread.ID?
    ) -> [BrowserThread] {
        guard threads.count > maxThreads else {
            return threads
        }

        var cappedThreads = Array(threads.suffix(maxThreads))
        guard let selectedThreadID,
              cappedThreads.contains(where: { $0.id == selectedThreadID }) == false,
              let selectedThread = threads.first(where: { $0.id == selectedThreadID }) else {
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
