import Foundation

/// Deterministic cleanup after speech recognition. It only removes hesitation sounds and applies
/// the user's replacements, so it can never invent text.
public enum TextCleanup {
    public struct Replacement: Equatable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public static let defaultReplacementsText = """
    merchen -> mergen
    Cloud Code -> Claude Code
    Whisper Flow -> Wispr Flow
    Hot Key -> Hotkey
    """

    /// "um", "also" and "halt" stay on purpose: they are real German words.
    private static let filler = "(?:ä+h+m*|ä+m+|ö+h+m*|h+m+|u+h+m+|u+h+)"

    public static func parseReplacements(_ text: String) -> [Replacement] {
        text.components(separatedBy: .newlines).compactMap { line in
            // Only the first arrow separates, so a correction may contain one itself.
            let separators = [line.range(of: "->"), line.range(of: "→")].compactMap { $0 }
            guard let separator = separators.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
            let parts = [String(line[..<separator.lowerBound]), String(line[separator.upperBound...])]
            let from = parts[0].trimmingCharacters(in: .whitespaces)
            let to = parts[1].trimmingCharacters(in: .whitespaces)
            return from.isEmpty ? nil : Replacement(from: from, to: to)
        }
    }

    public static func clean(_ text: String, replacements: [Replacement] = []) -> String {
        var result = removeFillers(text)
        // Longest first, so a phrase wins over a shorter phrase inside it.
        for replacement in replacements.sorted(by: { $0.from.count > $1.from.count }) {
            let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: replacement.from))(?![\\p{L}\\p{N}])"
            result = result.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: replacement.to), options: [.regularExpression, .caseInsensitive])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeFillers(_ text: String) -> String {
        // At a sentence start the next word takes over the capital letter.
        var result = capitalizeAfterLeadingFiller(text)
        // ", äh," keeps one comma, because the sentence around it may need it.
        result = result.replacingOccurrences(of: ",\\s*\(filler),", with: ",", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "(?:,\\s*)?(?<![\\p{L}\\p{N}])\(filler)(?![\\p{L}\\p{N}])(?:,+)?", with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+([,.?!:;])", with: "$1", options: .regularExpression)
        return result
    }

    private static func capitalizeAfterLeadingFiller(_ text: String) -> String {
        let pattern = "(^|[.?!]\\s+)\(filler)[,.…]*\\s+(\\p{Ll})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: result),
                  let prefix = Range(match.range(at: 1), in: result),
                  let letter = Range(match.range(at: 2), in: result) else { continue }
            result.replaceSubrange(whole, with: result[prefix] + result[letter].uppercased())
        }
        return result
    }
}
