import Foundation

struct ShortcutOverride: Codable, Equatable {
    var binding: ShortcutBinding?
}

struct ShortcutPreferencesStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "Tungsten.ShortcutOverrides.v1") {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadOverrides() -> [ShortcutActionID: ShortcutOverride] {
        guard let data = userDefaults.data(forKey: key) else {
            return [:]
        }

        do {
            let rawOverrides = try JSONDecoder().decode([String: ShortcutOverride].self, from: data)
            return rawOverrides.reduce(into: [:]) { result, element in
                guard let id = ShortcutActionID(rawValue: element.key) else {
                    return
                }
                if let binding = element.value.binding, binding.isUsable == false {
                    return
                }
                result[id] = element.value
            }
        } catch {
            return [:]
        }
    }

    func saveOverrides(_ overrides: [ShortcutActionID: ShortcutOverride]) {
        let rawOverrides = overrides.reduce(into: [String: ShortcutOverride]()) { result, element in
            result[element.key.rawValue] = element.value
        }

        guard let data = try? JSONEncoder().encode(rawOverrides) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }
}
