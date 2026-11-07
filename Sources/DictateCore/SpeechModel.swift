import FluidAudio
import Foundation

/// The speech models the app offers. Only the selected one stays in memory.
public enum SpeechModel: String, CaseIterable, Identifiable {
    case nemotron
    case parakeetUltra

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nemotron:      return "NVIDIA Nemotron"
        case .parakeetUltra: return "Parakeet Ultra"
        }
    }

    /// Whether text appears at the cursor during speech, or only once at the end.
    public var typesLive: Bool { self == .nemotron }

    public func makeTranscriber() -> SpeechTranscriber {
        switch self {
        case .nemotron:      return NemotronTranscriber()
        case .parakeetUltra: return ParakeetUltraTranscriber()
        }
    }

    private static var modelsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }

    private var folder: URL {
        switch self {
        case .nemotron:      return Self.modelsDirectory.appendingPathComponent("nemotron-labs-unified-asr", isDirectory: true)
        case .parakeetUltra: return Self.modelsDirectory.appendingPathComponent("parakeet-ultra", isDirectory: true)
        }
    }

    /// Fetches the files without loading the model, so memory only ever holds the selected one.
    public func download(to directory: URL? = nil, onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        let repo: Repo
        let files: Set<String>
        switch self {
        case .nemotron:
            repo = NemotronTranscriber.config.family.repo
            files = NemotronTranscriber.requiredFiles
        case .parakeetUltra:
            repo = .parakeetUltra
            files = []
        }
        try await ModelHub.download(repo, to: directory ?? Self.modelsDirectory, additionalModelNames: files) { progress in
            if case .downloading = progress.phase {
                onProgress?(progress.fractionCompleted)
            }
        }
    }

    public var isInstalled: Bool {
        let encoder: String
        switch self {
        case .nemotron:      encoder = "coreml/nemotron_unified_encoder_streaming_70_13_13_int8.mlmodelc"
        case .parakeetUltra: encoder = "Encoder.mlmodelc"
        }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(encoder).path)
    }

    public func uninstall() throws {
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }
}
