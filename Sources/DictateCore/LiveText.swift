import Foundation

/// Decides what to type at the cursor while the transcript is still growing.
public enum LiveText {
    public struct Edit: Equatable {
        public let deleteCount: Int
        public let insert: String

        public init(deleteCount: Int, insert: String) {
            self.deleteCount = deleteCount
            self.insert = insert
        }
    }

    /// The part of a partial transcript that is safe to type. The newest words are held back,
    /// because they may still grow or match a replacement.
    public static func stablePrefix(of text: String, holdBackWords: Int) -> String {
        var remaining = max(1, holdBackWords)
        var inWord = false
        var index = text.endIndex
        while index > text.startIndex {
            let previous = text.index(before: index)
            if text[previous].isWhitespace {
                if inWord {
                    remaining -= 1
                    if remaining == 0 { return String(text[..<index]) }
                }
                inWord = false
            } else {
                inWord = true
            }
            index = previous
        }
        return ""
    }

    /// The smallest change at the end of the typed text that produces the target.
    public static func edit(from typed: String, to target: String) -> Edit {
        let common = typed.commonPrefix(with: target).count
        return Edit(deleteCount: typed.count - common, insert: String(target.dropFirst(common)))
    }

    public static func holdBackWords(for replacements: [TextCleanup.Replacement]) -> Int {
        let longest = replacements.map { $0.from.split(whereSeparator: \.isWhitespace).count }.max() ?? 1
        return max(1, longest)
    }
}
