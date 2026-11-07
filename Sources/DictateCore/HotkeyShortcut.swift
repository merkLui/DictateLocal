import Foundation

/// How the shortcut starts and ends a dictation.
public enum HotkeyMode: String, CaseIterable {
    case holdOrPress
    case hold
    case press
}

/// One to three keys pressed together, identified by hardware key code.
public struct HotkeyShortcut: Codable, Equatable {
    public struct Key: Codable, Equatable {
        public let code: UInt16
        public let label: String

        public init(code: UInt16, label: String) {
            self.code = code
            self.label = label
        }
    }

    public enum ValidationError: Error, Equatable {
        case tooManyKeys
        case needsModifier
    }

    public static let fnCode: UInt16 = 63
    public static let `default` = HotkeyShortcut(keys: [Key(code: fnCode, label: "fn")])

    private static let modifierLabels: [UInt16: String] = [
        54: "right ⌘", 55: "⌘",
        56: "⇧", 60: "right ⇧",
        58: "⌥", 61: "right ⌥",
        59: "⌃", 62: "right ⌃",
        fnCode: "fn"
    ]
    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]
    private static let shiftCodes: Set<UInt16> = [56, 60]

    public let keys: [Key]

    public init(keys: [Key]) {
        self.keys = keys
    }

    public var codes: Set<UInt16> { Set(keys.map(\.code)) }

    public var isModifierOnly: Bool { keys.allSatisfy { Self.isModifier($0.code) } }

    public static func isModifier(_ code: UInt16) -> Bool {
        modifierLabels[code] != nil
    }

    public static func modifierLabel(for code: UInt16) -> String? {
        modifierLabels[code]
    }

    /// Letters and similar keys need a modifier, otherwise normal typing would start dictation.
    public func validate() -> ValidationError? {
        guard !keys.isEmpty, keys.count <= 3 else { return .tooManyKeys }
        let regular = keys.filter { !Self.isModifier($0.code) }
        guard regular.count <= 1 else { return .needsModifier }
        guard let key = regular.first, !Self.functionKeyCodes.contains(key.code) else { return nil }
        let hasRealModifier = keys.contains { Self.isModifier($0.code) && !Self.shiftCodes.contains($0.code) }
        return hasRealModifier ? nil : .needsModifier
    }
}

/// Tracks which keys are down and reports when the shortcut starts and ends.
public struct HotkeyMatcher {
    public enum Event: Equatable {
        case activated
        case deactivated
        case interrupted
    }

    public var shortcut: HotkeyShortcut {
        didSet { reset() }
    }
    public private(set) var isActive = false
    private var pressed = Set<UInt16>()

    public init(shortcut: HotkeyShortcut) {
        self.shortcut = shortcut
    }

    public mutating func reset() {
        pressed.removeAll()
        isActive = false
    }

    /// Ends the current activation; it starts again only after the keys match exactly once more.
    public mutating func deactivate() {
        isActive = false
    }

    public mutating func handle(code: UInt16, isDown: Bool) -> Event? {
        if isDown {
            pressed.insert(code)
            if !isActive, pressed == shortcut.codes {
                isActive = true
                return .activated
            }
            if isActive, !shortcut.codes.contains(code) {
                return .interrupted
            }
            return nil
        }

        pressed.remove(code)
        if isActive, shortcut.codes.contains(code) {
            isActive = false
            return .deactivated
        }
        return nil
    }
}
