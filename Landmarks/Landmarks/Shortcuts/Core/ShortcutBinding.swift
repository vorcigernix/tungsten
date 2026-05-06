import AppKit
import Foundation

struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let shift = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let control = ShortcutModifiers(rawValue: 1 << 3)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(eventModifiers: NSEvent.ModifierFlags) {
        var modifiers: ShortcutModifiers = []
        if eventModifiers.contains(.command) {
            modifiers.insert(.command)
        }
        if eventModifiers.contains(.shift) {
            modifiers.insert(.shift)
        }
        if eventModifiers.contains(.option) {
            modifiers.insert(.option)
        }
        if eventModifiers.contains(.control) {
            modifiers.insert(.control)
        }
        self = modifiers
    }

    var containsNonShiftModifier: Bool {
        contains(.command) || contains(.option) || contains(.control)
    }

    var displayParts: [String] {
        var parts: [String] = []
        if contains(.command) {
            parts.append("Command")
        }
        if contains(.option) {
            parts.append("Option")
        }
        if contains(.control) {
            parts.append("Control")
        }
        if contains(.shift) {
            parts.append("Shift")
        }
        return parts
    }
}

struct ShortcutBinding: Codable, Equatable, Hashable {
    static let tabKey = "tab"
    static let leftArrowKey = "leftArrow"
    static let rightArrowKey = "rightArrow"
    static let upArrowKey = "upArrow"
    static let downArrowKey = "downArrow"

    var key: String
    var modifiers: ShortcutModifiers

    init(key: String, modifiers: ShortcutModifiers) {
        self.key = Self.normalizedKey(key)
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let key: String
        switch event.keyCode {
        case 48:
            key = Self.tabKey
        case 123:
            key = Self.leftArrowKey
        case 124:
            key = Self.rightArrowKey
        case 125:
            key = Self.downArrowKey
        case 126:
            key = Self.upArrowKey
        default:
            guard let rawKey = event.charactersIgnoringModifiers, rawKey.isEmpty == false else {
                return nil
            }
            key = rawKey
        }

        self.init(key: key, modifiers: ShortcutModifiers(eventModifiers: event.modifierFlags))

        guard isUsable else {
            return nil
        }
    }

    var isUsable: Bool {
        key.isEmpty == false && modifiers.containsNonShiftModifier
    }

    var displayString: String {
        (modifiers.displayParts + [displayKey]).joined(separator: "-")
    }

    private var displayKey: String {
        switch key {
        case Self.tabKey:
            return "Tab"
        case Self.leftArrowKey:
            return "Left Arrow"
        case Self.rightArrowKey:
            return "Right Arrow"
        case Self.upArrowKey:
            return "Up Arrow"
        case Self.downArrowKey:
            return "Down Arrow"
        case "[":
            return "["
        case "]":
            return "]"
        case "+", "-", "0"..."9":
            return key
        default:
            return key.uppercased()
        }
    }

    private static func normalizedKey(_ key: String) -> String {
        switch key {
        case tabKey, leftArrowKey, rightArrowKey, upArrowKey, downArrowKey:
            return key
        default:
            return key.lowercased()
        }
    }
}
