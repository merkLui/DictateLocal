import AVFoundation
import Foundation
import FluidAudio

/// The one speech engine the app talks to, so the model can be swapped without touching the app.
public protocol SpeechTranscriber: AnyObject {
    /// Loads the model and downloads it on first use. Safe to call repeatedly.
    /// `onDownload` reports the fraction completed, only while files are actually downloading.
    func prepare(onDownload: (@Sendable (Double) -> Void)?) async throws
    func append(_ buffer: AVAudioPCMBuffer) async throws
    func partialTranscript() async -> String
    func finish() async throws -> String
    func reset() async throws
    /// Stops any load still running and frees the model's memory. The transcriber cannot be prepared again.
    func unload() async
}

public extension SpeechTranscriber {
    func prepare() async throws {
        try await prepare(onDownload: nil)
    }
}

/// NVIDIA Nemotron Unified ASR 0.6B: int8 encoder, 2.08 s streaming tier, German language prompt.
public final class NemotronTranscriber: SpeechTranscriber {
    static let config = UnifiedConfig(leftFrames: 70, chunkFrames: 13, rightFrames: 13, family: .nemotronMultilingual(.de))
    static var requiredFiles: Set<String> {
        let family = config.family
        return [
            family.streamingEncoderFile(precision: .int8, contextSuffix: config.contextSuffix),
            family.decoderFile,
            family.jointDecisionFile,
            family.vocab,
        ]
    }

    private let manager = StreamingUnifiedAsrManager(config: NemotronTranscriber.config, encoderPrecision: .int8)
    private let lock = NSLock()
    private var loadTask: Task<Void, Error>?
    private var isUnloaded = false

    public init() {}

    public func prepare(onDownload: (@Sendable (Double) -> Void)?) async throws {
        lock.lock()
        guard !isUnloaded else {
            lock.unlock()
            throw CancellationError()
        }
        let task = loadTask ?? Task { [manager] in
            try await manager.loadModels(to: nil, configuration: nil) { progress in
                if case .downloading = progress.phase {
                    onDownload?(progress.fractionCompleted)
                }
            }
        }
        loadTask = task
        lock.unlock()

        do {
            try await task.value
        } catch {
            // Allow a later attempt, for example once the network is back.
            lock.lock()
            loadTask = nil
            lock.unlock()
            throw error
        }
    }

    public func append(_ buffer: AVAudioPCMBuffer) async throws {
        try await manager.appendAudio(buffer)
        try await manager.processBufferedAudio()
        // Unused here; without draining they would grow for the whole dictation.
        _ = await manager.consumeTokenTimings()
    }

    public func partialTranscript() async -> String {
        await manager.getPartialTranscript()
    }

    public func finish() async throws -> String {
        try await manager.finish()
    }

    public func reset() async throws {
        try await manager.reset()
    }

    public func unload() async {
        lock.lock()
        isUnloaded = true
        let task = loadTask
        loadTask = nil
        lock.unlock()

        task?.cancel()
        _ = try? await task?.value
        await manager.cleanup()
    }
}

/// Parakeet Ultra has no streaming mode, so it collects the audio and decodes it once on release.
public actor ParakeetUltraTranscriber: SpeechTranscriber {
    private static let sampleRate = 16_000

    private let manager = AsrManager()
    private let converter = AudioConverter()
    private var loadTask: Task<Void, Error>?
    private var samples: [Float] = []
    private var isUnloaded = false

    public init() {}

    public func prepare(onDownload: (@Sendable (Double) -> Void)?) async throws {
        guard !isUnloaded else { throw CancellationError() }
        let task = loadTask ?? Task { [manager] in
            let models = try await AsrModels.downloadAndLoad(version: .ultra) { progress in
                if case .downloading = progress.phase {
                    onDownload?(progress.fractionCompleted)
                }
            }
            try await manager.loadModels(models)
        }
        loadTask = task

        do {
            try await task.value
        } catch {
            loadTask = nil
            throw error
        }
    }

    public func append(_ buffer: AVAudioPCMBuffer) async throws {
        samples.append(contentsOf: try converter.resampleBuffer(buffer))
    }

    public func partialTranscript() async -> String {
        ""
    }

    public func finish() async throws -> String {
        guard samples.count >= Self.sampleRate / 4 else { return "" }
        var state = TdtDecoderState.make()
        return try await manager.transcribe(samples, decoderState: &state, language: nil).text
    }

    public func reset() async throws {
        samples.removeAll()
    }

    public func unload() async {
        isUnloaded = true
        let task = loadTask
        loadTask = nil

        task?.cancel()
        _ = try? await task?.value
        await manager.cleanup()
    }
}
