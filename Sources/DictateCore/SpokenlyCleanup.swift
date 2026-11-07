import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

/// Spokenly Cleanup 1, a Qwen3-0.6B fine-tune for dictated text, running through MLX.
/// It loads when dictation starts and leaves memory after five idle minutes.
public actor SpokenlyCleanup {
    private static let revision = "a83ba762e3c4ab6a3a20814ec68050f381d92cf8"
    private static let baseURL = "https://huggingface.co/spokenly/cleanup-1/resolve/\(revision)/"
    private static let keptFiles = ["config.json", "tokenizer.json", "LICENSE", "NOTICE"]
    private static let endTokens: Set<Int> = [151643, 151645]
    private static let idleSeconds: UInt64 = 300
    /// Sentences are cleaned in groups, so one rejected result only costs that group.
    private static let wordsPerChunk = 60

    private static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("DictateLocal/Models/spokenly-cleanup-1-4bit", isDirectory: true)
    }

    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private var idleTimer: Task<Void, Never>?
    /// Keeps its model in memory until it has stopped, even after a time limit or an unload.
    private var generation: Task<String, Error>?

    public init() {}

    public nonisolated static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("model.safetensors").path)
    }

    /// The official weights only exist in 16 bit, so they are downloaded once and reduced to 4 bit here.
    /// Progress covers the download; reducing the weights follows at 1.
    public func install(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard !Self.isInstalled else { return }
        let manager = FileManager.default
        let source = manager.temporaryDirectory.appendingPathComponent("spokenly-cleanup-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: source) }

        for file in Self.keptFiles + ["model.safetensors.index.json"] {
            try await Self.fetch(file, to: source, onProgress: nil)
        }
        try await Self.fetch("model.safetensors", to: source) { onProgress?($0) }

        let target = manager.temporaryDirectory.appendingPathComponent("spokenly-cleanup-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: target) }

        do {
            let full = try await loadModelContainer(from: source, using: BPELoader())
            try await full.perform { (context: ModelContext) in
                quantize(model: context.model, groupSize: 64, bits: 4)
                let weights = Dictionary(uniqueKeysWithValues: context.model.parameters().flattened())
                eval(Array(weights.values))
                try save(arrays: weights, metadata: ["format": "mlx"], url: target.appendingPathComponent("model.safetensors"))
            }
        }
        Self.freeMemory()

        for file in ["tokenizer.json", "LICENSE", "NOTICE"] {
            try manager.copyItem(at: source.appendingPathComponent(file), to: target.appendingPathComponent(file))
        }
        var config = try JSONSerialization.jsonObject(with: Data(contentsOf: source.appendingPathComponent("config.json"))) as? [String: Any] ?? [:]
        config["quantization"] = ["group_size": 64, "bits": 4, "mode": "affine"]
        try JSONSerialization.data(withJSONObject: config).write(to: target.appendingPathComponent("config.json"))

        try manager.createDirectory(at: Self.folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.removeItem(at: Self.folder)
        try manager.moveItem(at: target, to: Self.folder)
    }

    public func uninstall() async throws {
        await unload()
        if FileManager.default.fileExists(atPath: Self.folder.path) {
            try FileManager.default.removeItem(at: Self.folder)
        }
    }

    /// Called when dictation starts, so the model is ready by the time the key is released.
    public func prepare() async {
        _ = try? await loadedContainer()
    }

    public func unload() async {
        idleTimer?.cancel()
        idleTimer = nil
        generation?.cancel()
        _ = try? await generation?.value
        _ = try? await loading?.value
        loading = nil
        container = nil
        Self.freeMemory()
    }

    /// MLX keeps freed buffers for reuse, so they only go back to the system with its cache limit at zero.
    private static func freeMemory() {
        let limit = Memory.cacheLimit
        Memory.cacheLimit = 0
        Memory.clearCache()
        Memory.cacheLimit = limit
    }

    /// Returns the cleaned text, or the original if the model fails or takes longer than the timeout.
    public nonisolated func polish(_ text: String, timeout: TimeInterval) async -> String {
        // MLX generated about three times slower at user-initiated priority in our measurements.
        let work = Task.detached(priority: .medium) { [self] in try await clean(text) }
        let answer = OnceAnswer()
        return await withCheckedContinuation { continuation in
            answer.continuation = continuation
            Task.detached(priority: .medium) {
                answer.give((try? await work.value) ?? text)
            }
            // Generation only stops between tokens, so dictation does not wait for it to notice.
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                work.cancel()
                answer.give(text)
            }
        }
    }

    /// Anything the guard rejects stays as it was spoken.
    public func clean(_ text: String) async throws -> String {
        _ = try? await generation?.value
        let model = try await loadedContainer()
        let task = Task {
            var result: [String] = []
            for chunk in Self.chunks(of: text) {
                try Task.checkCancellation()
                let cleaned = try await Self.generate(chunk, with: model)
                result.append(CleanupGuard.accepts(source: chunk, output: cleaned) ? cleaned : chunk)
            }
            return result.joined(separator: " ")
        }
        generation = task
        defer { restartIdleTimer() }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func loadedContainer() async throws -> ModelContainer {
        defer { restartIdleTimer() }
        if let container { return container }
        // A model on its way out has to be gone first, so two are never in memory together.
        _ = try? await generation?.value
        if let container { return container }
        let task = loading ?? Task {
            Memory.cacheLimit = 64 * 1024 * 1024
            return try await loadModelContainer(from: Self.folder, using: BPELoader())
        }
        loading = task
        defer { loading = nil }
        let loaded = try await task.value
        container = loaded
        return loaded
    }

    private func restartIdleTimer() {
        idleTimer?.cancel()
        idleTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }

    private static func chunks(of text: String) -> [String] {
        var chunks: [String] = []
        var current: [String] = []
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { sentence, _, _, _ in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            let words = sentence.split(separator: " ").count
            if count + words > wordsPerChunk, !current.isEmpty {
                chunks.append(current.joined(separator: " "))
                current = []
                count = 0
            }
            current.append(sentence)
            count += words
        }
        if !current.isEmpty { chunks.append(current.joined(separator: " ")) }
        return chunks
    }

    private static func generate(_ text: String, with model: ModelContainer) async throws -> String {
        try await model.perform { (context: ModelContext) in
            let prompt = context.tokenizer.encode(text: "text: \(text)\nout:\n", addSpecialTokens: false)
            let parameters = GenerateParameters(maxTokens: prompt.count * 2 + 32, temperature: 0)
            let iterator = try TokenIterator(input: LMInput(tokens: MLXArray(prompt)), model: context.model, parameters: parameters)
            var tokens: [Int] = []
            for token in iterator {
                if endTokens.contains(token) { break }
                try Task.checkCancellation()
                tokens.append(token)
            }
            return context.tokenizer.decode(tokenIds: tokens, skipSpecialTokens: true)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func fetch(_ file: String, to folder: URL, onProgress: (@Sendable (Double) -> Void)?) async throws {
        guard let url = URL(string: baseURL + file) else { throw URLError(.badURL) }
        let delegate = DownloadProgress(onProgress: onProgress)
        let (location, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try FileManager.default.moveItem(at: location, to: folder.appendingPathComponent(file))
    }
}

/// Whichever finishes first answers: the cleaned text or the time limit.
private final class OnceAnswer: @unchecked Sendable {
    private let lock = NSLock()
    var continuation: CheckedContinuation<String, Never>?

    func give(_ text: String) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: text)
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (@Sendable (Double) -> Void)?

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
