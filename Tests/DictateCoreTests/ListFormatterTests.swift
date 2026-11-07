import DictateCore
import Testing

@Suite("List formatting")
struct ListFormatterTests {
    @Test("Turns explicit enumerations into lists", arguments: [
        ("Einkaufsliste: eine Gurke, eine Tomate, eine Zwiebel und zwei Paprika.", "Einkaufsliste:\n- eine Gurke\n- eine Tomate\n- eine Zwiebel\n- zwei Paprika"),
        ("Erstens den Branch mergen, zweitens das Deployment starten, drittens die Logs prüfen.", "1. den Branch mergen\n2. das Deployment starten\n3. die Logs prüfen"),
        ("Punkt 1: Budget klären, Punkt 2: Timeline festlegen.", "1. Budget klären\n2. Timeline festlegen"),
    ])
    func lists(input: String, expected: String) {
        #expect(ListFormatter.format(input) == expected)
    }

    @Test("Leaves ordinary sentences alone", arguments: [
        "Übersetze auf Englisch: Ich komme heute etwas später, weil mein Zug ausgefallen ist.",
        "Ich brauche für morgen Milch, Eier, Butter und Mehl.",
        "Erstens und zweitens sind hier nur Beispielwörter.",
        "Wir treffen uns um elf, also passt das.",
    ])
    func prose(sentence: String) {
        #expect(ListFormatter.format(sentence) == sentence)
    }
}
