import DictateCore
import Testing

@Suite("Shortcut")
struct HotkeyShortcutTests {
    static let fn = HotkeyShortcut.Key(code: 63, label: "fn")
    static let control = HotkeyShortcut.Key(code: 59, label: "⌃")
    static let shift = HotkeyShortcut.Key(code: 56, label: "⇧")
    static let space = HotkeyShortcut.Key(code: 49, label: "Space")
    static let letter = HotkeyShortcut.Key(code: 0, label: "A")
    static let f5 = HotkeyShortcut.Key(code: 96, label: "F5")

    @Test("Accepts modifier and function keys, rejects typing keys alone", arguments: [
        ([fn], nil),
        ([f5], nil),
        ([control, space], nil),
        ([control, shift], nil),
        ([letter], .needsModifier),
        ([space], .needsModifier),
        ([shift, letter], .needsModifier),
        ([letter, space, control], .needsModifier),
        ([fn, control, shift, space], .tooManyKeys),
    ] as [([HotkeyShortcut.Key], HotkeyShortcut.ValidationError?)])
    func validation(keys: [HotkeyShortcut.Key], error: HotkeyShortcut.ValidationError?) {
        #expect(HotkeyShortcut(keys: keys).validate() == error)
    }

    @Test("Fires only for the exact key combination", arguments: [
        ([fn], [(63, true), (63, false)], [.activated, .deactivated]),
        ([control, space], [(59, true), (49, true), (49, false), (59, false)], [.activated, .deactivated]),
        ([control, space], [(49, true), (59, true), (59, false), (49, false)], [.activated, .deactivated]),
        ([control, space], [(59, true), (59, false), (49, true), (49, false)], []),
        ([fn], [(56, true), (63, true), (63, false), (56, false)], []),
        ([fn], [(63, true), (0, true), (0, false), (63, false)], [.activated, .interrupted, .deactivated]),
    ] as [([HotkeyShortcut.Key], [(UInt16, Bool)], [HotkeyMatcher.Event])])
    func matching(keys: [HotkeyShortcut.Key], steps: [(UInt16, Bool)], expected: [HotkeyMatcher.Event]) {
        var matcher = HotkeyMatcher(shortcut: HotkeyShortcut(keys: keys))
        let events = steps.compactMap { matcher.handle(code: $0.0, isDown: $0.1) }
        #expect(events == expected)
    }
}
