import DictateCore
import Testing

@Suite("Live typing")
struct LiveTextTests {
    @Test("Holds back the last words, which may still change", arguments: [
        ("Der Fix ist Re", 1, "Der Fix ist "),
        ("Der Fix ist Re", 2, "Der Fix "),
        ("Der", 1, ""),
        ("", 1, ""),
    ])
    func stablePrefix(text: String, holdBack: Int, expected: String) {
        #expect(LiveText.stablePrefix(of: text, holdBackWords: holdBack) == expected)
    }

    @Test("Edits only the changed tail", arguments: [
        ("", "Der ", 0, "Der "),
        ("Der ", "Der Fix ", 0, "Fix "),
        ("Der Fi ", "Der Fix ", 1, "x "),
        ("Der Fix ", "Der Fix ", 0, ""),
    ])
    func edit(typed: String, target: String, deleteCount: Int, insert: String) {
        #expect(LiveText.edit(from: typed, to: target) == .init(deleteCount: deleteCount, insert: insert))
    }
}
