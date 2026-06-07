import Foundation

enum ShortcutAssignmentResult: Equatable {
    case assigned
    case invalid
    case unavailable
    case conflict(existingAction: ShortcutActionID)
}

final class ShortcutManager {
    let actions: [ShortcutAction]

    private let store: ShortcutPreferencesStore
    private var overrides: [ShortcutActionID: ShortcutOverride]

    init(actions: [ShortcutAction] = ShortcutCatalog.actions, store: ShortcutPreferencesStore = ShortcutPreferencesStore()) {
        self.actions = actions
        self.store = store
        self.overrides = store.loadOverrides()
    }

    func action(id: ShortcutActionID) -> ShortcutAction? {
        actions.first { $0.id == id }
    }

    func actions(in category: ShortcutCategory) -> [ShortcutAction] {
        actions.filter { $0.category == category }
    }

    func activeBindings(for actionID: ShortcutActionID) -> [ShortcutBinding] {
        guard let action = action(id: actionID) else {
            return []
        }

        if let override = overrides[actionID] {
            if let binding = override.binding {
                return [binding]
            }
            return []
        }

        return action.defaultBindings
    }

    func setCustomBinding(_ binding: ShortcutBinding, for actionID: ShortcutActionID) -> ShortcutAssignmentResult {
        guard binding.isUsable else {
            return .invalid
        }
        guard let action = action(id: actionID), action.isAvailable else {
            return .unavailable
        }
        if let conflict = conflicts(for: binding, excluding: actionID).first {
            return .conflict(existingAction: conflict.id)
        }

        overrides[actionID] = ShortcutOverride(binding: binding)
        store.saveOverrides(overrides)
        return .assigned
    }

    func clearBinding(for actionID: ShortcutActionID) {
        guard let action = action(id: actionID), action.isAvailable else {
            return
        }

        overrides[actionID] = ShortcutOverride(binding: nil)
        store.saveOverrides(overrides)
    }

    func resetBinding(for actionID: ShortcutActionID) {
        overrides.removeValue(forKey: actionID)
        store.saveOverrides(overrides)
    }

    func conflicts(for binding: ShortcutBinding, excluding actionID: ShortcutActionID? = nil) -> [ShortcutAction] {
        actions.filter { action in
            guard action.isAvailable else {
                return false
            }
            if action.id == actionID {
                return false
            }
            return activeBindings(for: action.id).contains(binding)
        }
    }

    func dispatchableAction(for binding: ShortcutBinding) -> ShortcutAction? {
        let matches = actions.filter { action in
            action.isAvailable && activeBindings(for: action.id).contains(binding)
        }

        guard matches.count == 1 else {
            return nil
        }

        return matches[0]
    }

    func displayString(for actionID: ShortcutActionID) -> String {
        let bindings = activeBindings(for: actionID)
        guard bindings.isEmpty == false else {
            return "Unassigned"
        }
        return bindings.map(\.displayString).joined(separator: ", ")
    }
}
