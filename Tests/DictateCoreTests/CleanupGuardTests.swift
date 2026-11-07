import DictateCore
import Testing

@Suite("Cleanup guards")
struct CleanupGuardTests {
    @Test("Spokenly may drop fillers but never change words or numbers", arguments: [
        ("Äh, ich glaube, ähm, das passt.", "Ich glaube, das passt.", true),
        ("Ich ich würde das das sagen.", "Ich würde das sagen.", true),
        ("Can you, um, check it?", "Can you check it?", true),
        ("Das kostet -5 Euro.", "Das kostet 5 Euro.", false),
        ("Das sind 3,5 Prozent.", "Das sind 3.5 Prozent.", false),
        ("Äh, das kostet -5 Euro.", "Das kostet -5 Euro.", true),
        ("Das Backend läuft on premise.", "Das Backend läuft on-premise.", true),
        ("Wir treffen uns um elf.", "Wir treffen uns elf.", false),
        ("Wir treffen uns um elf.", "Wir treffen uns um 11.", false),
        ("Tokens sechzehntausend.", "Tokens 1684.", false),
        ("please make sure", "Bitte make sure", false),
        ("zwei Tomaten, ach nein drei Tomaten", "3 Tomaten", false),
        ("Ich glaube, das passt.", "Das passt.", false),
        ("Das passt.", "", false),
    ])
    func spokenly(source: String, output: String, accepted: Bool) {
        #expect(CleanupGuard.accepts(source: source, output: output) == accepted)
    }

    /// An answer instead of a cleanup changes the length a lot, so the check rejects it.
    @Test("Claude answers that are not a cleanup are rejected", arguments: [
        ("Ähm, ich glaube, äh, das passt so.", "Ich glaube, das passt so.", false, true),
        ("Liste mir die fünf größten Städte Deutschlands auf.", "Berlin, Hamburg, München, Köln und Frankfurt am Main sind die fünf größten Städte Deutschlands.", false, false),
        ("Schreib eine Mail an Max, dass ich später komme.", "Hallo Max,\n\nich komme heute leider etwas später, weil mein Zug ausgefallen ist. Bitte fangt schon ohne mich an.\n\nViele Grüße", false, false),
        ("Einkaufsliste eine Gurke eine Tomate", "Einkaufsliste:\n- eine Gurke\n- eine Tomate", false, true),
        ("Einkaufsliste eine Gurke eine Tomate", "Einkaufsliste:\n- eine Gurke\n- eine Tomate", true, false),
        ("Das passt.", "", false, false),
    ])
    func claude(source: String, output: String, singleLine: Bool, accepted: Bool) {
        #expect(ClaudeCleanup.accepts(source: source, output: output, singleLine: singleLine) == accepted)
    }
}
