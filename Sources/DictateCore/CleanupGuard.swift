import Foundation

/// Decides whether a model's cleanup may be used: it may only drop filler words and stutters.
public enum CleanupGuard {
    private static let fillers: Set<String> = [
        "äh", "ähm", "ah", "öh", "ehm", "hm", "hmm", "mhm", "uh", "uhm",
        "halt", "irgendwie", "sozusagen", "quasi", "also", "ja",
    ]

    private static func words(_ text: String) -> [String] {
        // "um" is a real German word, so it only counts as a filler when set off by a comma.
        let marked = text.replacingOccurrences(of: "\\bum,", with: "uhm,", options: [.regularExpression, .caseInsensitive])
        return marked.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// Numbers with their sign and separators, because "-5" and "5" are the same words to `words`.
    private static func numbers(_ text: String) -> [String] {
        let pattern = "[-−+]?\\d+(?:[.,:/]\\d+)*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    public static func accepts(source: String, output: String) -> Bool {
        guard numbers(source) == numbers(output) else { return false }
        let original = words(source)
        let cleaned = words(output)
        guard !cleaned.isEmpty || original.isEmpty else { return false }

        func mayDrop(_ index: Int) -> Bool {
            let word = original[index]
            let isStutter = (index > 0 && original[index - 1] == word)
                || (index + 1 < original.count && original[index + 1] == word)
            return fillers.contains(word) || isStutter
        }

        var index = 0
        for word in cleaned {
            while index < original.count, original[index] != word {
                guard mayDrop(index) else { return false }
                index += 1
            }
            guard index < original.count else { return false }
            index += 1
        }
        while index < original.count {
            guard mayDrop(index) else { return false }
            index += 1
        }
        return true
    }
}
