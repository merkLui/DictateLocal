import AVFoundation
import Foundation

/// One dictation: audio goes in live, partial text comes out, the final text is awaited on release.
/// Audio is queued, so speech captured while the model is still loading is not lost.
public final class DictationSession {
    private let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let lock = NSLock()
    private var isCancelled = false
    private var worker: Task<String, Error>!

    /// Finishes once the transcriber is reset and free for the next session.
    public var completion: Task<Void, Never> {
        let worker = self.worker!
        return Task { _ = try? await worker.value }
    }

    /// - Parameter previous: awaited first, because a transcriber handles one dictation at a time.
    public init(
        transcriber: SpeechTranscriber,
        after previous: Task<Void, Never>? = nil,
        partialInterval: TimeInterval = 0.25,
        onPartial: @escaping (String) -> Void
    ) {
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.continuation = continuation

        worker = Task { [weak self] in
            await previous?.value

            do {
                try await transcriber.prepare()

                var lastPartial = ""
                var lastPartialTime = Date.distantPast
                for await buffer in stream {
                    if self?.cancelled ?? true { break }
                    try await transcriber.append(buffer)
                    if self?.cancelled ?? true { break }

                    guard Date().timeIntervalSince(lastPartialTime) >= partialInterval else { continue }
                    lastPartialTime = Date()
                    let partial = await transcriber.partialTranscript()
                    if partial != lastPartial {
                        lastPartial = partial
                        onPartial(partial)
                    }
                }

                let text = (self?.cancelled ?? true) ? "" : try await transcriber.finish()
                try await transcriber.reset()
                return text
            } catch {
                // The next session must not inherit audio from a failed one.
                try? await transcriber.reset()
                throw error
            }
        }
    }

    public func append(_ buffer: AVAudioPCMBuffer) {
        continuation.yield(buffer)
    }

    public func finish() async throws -> String {
        continuation.finish()
        return try await worker.value
    }

    public func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
        continuation.finish()
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }
}
