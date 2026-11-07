import DictateCore
import Testing

@Suite("Text cleanup")
struct TextCleanupTests {
    @Test("Removes hesitation sounds but keeps real words", arguments: [
        ("Äh, ich glaube das passt.", "Ich glaube das passt."),
        ("Ich glaube, äh, das passt.", "Ich glaube, das passt."),
        ("Gut. Ähm wir machen das.", "Gut. Wir machen das."),
        ("Wir treffen uns um elf, also passt das halt.", "Wir treffen uns um elf, also passt das halt."),
        ("Der Zähler läuft.", "Der Zähler läuft."),
        ("Ich komme, äh. Morgen geht es weiter.", "Ich komme. Morgen geht es weiter."),
    ])
    func fillers(input: String, expected: String) {
        #expect(TextCleanup.clean(input) == expected)
    }

    @Test("Applies replacements to whole words in any case", arguments: [
        ("A geht", "B -> C geht", "A -> B -> C"),
        ("Der Fix ist ready, bitte nicht merchen.", "Der Fix ist ready, bitte nicht mergen.", "merchen -> mergen"),
        ("cloud code läuft", "Claude Code läuft", "Cloud Code → Claude Code"),
        ("Cloud Codex läuft", "Cloud Codex läuft", "Cloud Code -> Claude Code"),
        ("Kosten: 5 Euro", "Kosten: $1 Euro", "5 -> $1"),
    ])
    func replacements(input: String, expected: String, rules: String) {
        #expect(TextCleanup.clean(input, replacements: TextCleanup.parseReplacements(rules)) == expected)
    }
}
