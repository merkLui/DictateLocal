import Foundation
import MLXLMCommon

/// Byte-level BPE for Qwen tokenizers. Special tokens never appear in dictated text.
final class BPETokenizer: Tokenizer, @unchecked Sendable {
    private let vocab: [String: Int]
    private let reverse: [Int: String]
    private let ranks: [String: Int]
    private let byteToChar: [UInt8: Character]
    private let charToByte: [Character: UInt8]
    private let pattern: NSRegularExpression
    private static let separator = "\u{1}"

    init(directory: URL) throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("tokenizer.json"))) as! [String: Any]
        let model = json["model"] as! [String: Any]
        var vocab = model["vocab"] as! [String: Int]
        for added in json["added_tokens"] as! [[String: Any]] { vocab[added["content"] as! String] = added["id"] as? Int }
        self.vocab = vocab
        reverse = Dictionary(vocab.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var ranks: [String: Int] = [:]
        for (i, merge) in (model["merges"] as! [[String]]).enumerated() { ranks[merge[0] + Self.separator + merge[1]] = i }
        self.ranks = ranks
        var bytes = Array(UInt8(33)...UInt8(126)) + Array(UInt8(161)...UInt8(172)) + Array(UInt8(174)...UInt8(255))
        var codes = bytes.map { UInt32($0) }
        var n: UInt32 = 0
        for b in UInt8.min...UInt8.max where !bytes.contains(b) { bytes.append(b); codes.append(256 + n); n += 1 }
        var b2c: [UInt8: Character] = [:]; var c2b: [Character: UInt8] = [:]
        for (b, c) in zip(bytes, codes) { let ch = Character(UnicodeScalar(c)!); b2c[b] = ch; c2b[ch] = b }
        byteToChar = b2c; charToByte = c2b
        pattern = try NSRegularExpression(pattern: "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+")
    }

    private func bpe(_ piece: String) -> [Int] {
        var parts = piece.map(String.init)
        while parts.count > 1 {
            var best: (rank: Int, index: Int)?
            for i in 0..<(parts.count - 1) {
                if let r = ranks[parts[i] + Self.separator + parts[i + 1]], r < (best?.rank ?? .max) { best = (r, i) }
            }
            guard let best else { break }
            let first = parts[best.index], second = parts[best.index + 1]
            var merged: [String] = []; var i = 0
            while i < parts.count {
                if i < parts.count - 1, parts[i] == first, parts[i + 1] == second { merged.append(first + second); i += 2 } else { merged.append(parts[i]); i += 1 }
            }
            parts = merged
        }
        return parts.compactMap { vocab[$0] }
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        let text = text.precomposedStringWithCanonicalMapping as NSString
        var ids: [Int] = []
        for m in pattern.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let s = text.substring(with: m.range)
            ids += bpe(String(String.UnicodeScalarView(s.utf8.flatMap { byteToChar[$0]!.unicodeScalars })))
        }
        return ids
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        var bytes: [UInt8] = []
        for id in tokenIds where id < 151643 {
            for c in reverse[id] ?? "" { if let b = charToByte[c] { bytes.append(b) } }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
    func convertTokenToId(_ token: String) -> Int? { vocab[token] }
    func convertIdToToken(_ id: Int) -> String? { reverse[id] }
    var bosToken: String? { nil }
    var eosToken: String? { "<|endoftext|>" }
    var unknownToken: String? { nil }
    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?) throws -> [Int] { throw TokenizerError.missingChatTemplate }
}

struct BPELoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any Tokenizer { try BPETokenizer(directory: directory) }
}
