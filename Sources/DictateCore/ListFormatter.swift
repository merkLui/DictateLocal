import Foundation

/// Turns clearly dictated lists into lists and leaves everything else alone, because a false list
/// is worse than a missed one. Only "und", "and" and enumeration markers may disappear.
public enum ListFormatter {
    private static let ordinals = ["erstens", "zweitens", "drittens", "viertens", "fünftens", "sechstens"]
    private static let englishOrdinals = ["first", "second", "third", "fourth", "fifth", "sixth"]
    private static let numbers = ["eins", "zwei", "drei", "vier", "fünf", "sechs"]
    private static let finiteVerbs: Set<String> = Set("ist sind bin bist war waren wird werden wurde wurden habe hat haben hatte muss müssen kann können soll sollen weiß weiss brauche brauchen fehlt fehlen is are am was were has have needs looks".split(separator: " ").map(String.init))
    private static let pronouns: Set<String> = Set("ich du er sie es wir ihr man i you he she it we they".split(separator: " ").map(String.init))

    private static let word = regex("\\w+(?:[-’']\\w+)*")
    private static let marker = regex("(?i)\\b(?:\(ordinals.joined(separator: "|"))|\(englishOrdinals.joined(separator: "|"))|punkt\\s+(?:[1-6]|\(numbers.joined(separator: "|"))))\\b[: ,]*")
    private static let heading = regex("(?i)^((?:Einkaufsliste|Packliste|Checkliste|Shopping list|To-?dos|Aufgaben|Agenda)(?:\\s+(?:für|for|fürs)\\s+[^:,.!?]{1,35})?)\\s*[:,]\\s*(.+)$")
    private static let subordinate = regex("(?i)\\b(?:weil|dass|daß|wenn|obwohl|bevor|nachdem|falls|sodass|während|because|although|unless|whether)\\b")
    private static let conjunction = regex("(?i)\\b(?:und|and)\\b")
    private static let lastConjunction = regex("(?i)\\s+(und|and)\\s+")
    private static let notAnItem = regex("[\\n!?;:]|\\.\\s|[\"“”„]")

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants, so a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func contains(_ regex: NSRegularExpression, _ text: String) -> Bool {
        !matches(regex, text).isEmpty
    }

    private static func words(_ text: String) -> [String] {
        matches(word, text).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ".,; ").union(.whitespacesAndNewlines))
    }

    public static func format(_ text: String) -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.contains("\n"), source.count <= 1500 else { return text }
        return numberedList(source) ?? headedList(source) ?? text
    }

    /// "Erstens a, zweitens b": markers must start the text and count up from one.
    private static func numberedList(_ source: String) -> String? {
        let found = matches(marker, source)
        guard found.count >= 2, found[0].range.location == 0 else { return nil }

        var labels: [String] = []
        var ranks: [(family: Int, rank: Int)] = []
        for match in found {
            guard let range = Range(match.range, in: source) else { return nil }
            let label = String(source[range]).trimmingCharacters(in: CharacterSet(charactersIn: ": ,")).lowercased()
            labels.append(label)
            if let index = ordinals.firstIndex(of: label) {
                ranks.append((0, index + 1))
            } else if let index = englishOrdinals.firstIndex(of: label) {
                ranks.append((1, index + 1))
            } else if let last = label.split(whereSeparator: \.isWhitespace).last.map(String.init) {
                guard let rank = Int(last) ?? numbers.firstIndex(of: last).map({ $0 + 1 }) else { return nil }
                ranks.append((2, rank))
            }
        }
        guard ranks.map(\.rank) == Array(1...found.count), Set(ranks.map(\.family)).count == 1 else { return nil }

        var items: [String] = []
        for (index, match) in found.enumerated() {
            let start = match.range.location + match.range.length
            let end = index + 1 < found.count ? found[index + 1].range.location : (source as NSString).length
            items.append(trimmed((source as NSString).substring(with: NSRange(location: start, length: end - start))))
        }
        guard !items.contains(where: { $0.contains(",") }), itemsLookSafe(items, explicit: true) else { return nil }
        // "Erstens und zweitens sind hier nur Beispiele" mentions the markers instead of using them.
        guard !items.contains(where: { words($0).first?.lowercased() == "und" || words($0).first?.lowercased() == "and" }) else { return nil }
        if ranks[0].family == 2, items.contains(where: { finiteVerbs.contains(words($0).first?.lowercased() ?? "") }) { return nil }

        let removed = labels.flatMap { words($0) }
        let output = items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return keepsWords(source: source, output: output, removed: removed) ? output : nil
    }

    /// "Einkaufsliste: a, b und c". Item boundaries are never guessed from spaces.
    private static func headedList(_ source: String) -> String? {
        guard let match = matches(heading, source).first,
              let headRange = Range(match.range(at: 1), in: source),
              let bodyRange = Range(match.range(at: 2), in: source) else { return nil }
        let head = String(source[headRange])
        var chunks = trimmed(String(source[bodyRange])).components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard chunks.count >= 2, !chunks.contains(where: \.isEmpty) else { return nil }

        var removed: [String] = []
        // With "und" inside an earlier item it is unclear what belongs together, so all of them stay.
        if !chunks.dropLast().contains(where: { contains(conjunction, $0) }), let last = chunks.last {
            let joints = matches(lastConjunction, last)
            if joints.count == 1, let whole = Range(joints[0].range, in: last), let joint = Range(joints[0].range(at: 1), in: last) {
                chunks = chunks.dropLast() + [String(last[..<whole.lowerBound]), String(last[whole.upperBound...])]
                removed = [String(last[joint])]
            }
        }
        guard itemsLookSafe(chunks, explicit: false) else { return nil }
        let output = head + ":\n" + chunks.map { "- \($0)" }.joined(separator: "\n")
        return keepsWords(source: source, output: output, removed: removed) ? output : nil
    }

    private static func itemsLookSafe(_ items: [String], explicit: Bool) -> Bool {
        let lengths = items.map { words($0).count }
        guard (2...12).contains(items.count), lengths.allSatisfy({ (1...12).contains($0) }),
              let longest = lengths.max(), let shortest = lengths.min(), longest <= 4 * shortest + 2,
              !items.contains(where: { contains(notAnItem, $0) }) else { return false }
        guard !explicit else { return true }
        return !items.contains { item in
            let itemWords = words(item).map { $0.lowercased() }
            return contains(subordinate, item) || pronouns.contains(itemWords[0]) || !finiteVerbs.isDisjoint(with: itemWords)
        }
    }

    /// The output must be the source minus exactly the recorded words, in the same order.
    private static func keepsWords(source: String, output: String, removed: [String]) -> Bool {
        let prefix = regex("^(?:- |\\d+\\. )")
        let rendered = output.components(separatedBy: "\n").map { line in
            prefix.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
        }.joined(separator: "\n")
        let original = words(source)
        let kept = words(rendered)
        var removedIndex = 0
        var keptIndex = 0
        for token in original {
            if keptIndex < kept.count, token == kept[keptIndex] {
                keptIndex += 1
            } else if removedIndex < removed.count, token.lowercased() == removed[removedIndex].lowercased() {
                removedIndex += 1
            } else {
                return false
            }
        }
        return keptIndex == kept.count && removedIndex == removed.count
    }
}
