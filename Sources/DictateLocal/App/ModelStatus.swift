import DictateCore
import Foundation

/// Whether the speech model is ready, shown in Settings.
final class ModelStatus: ObservableObject {
    enum State: Equatable {
        case preparing
        case downloading(percent: Int)
        case ready
        case failed(String)
    }

    static let shared = ModelStatus()
    @Published var state: State = .preparing
    @Published var selected = AppDelegate.savedModel
    @Published var installed = Set(SpeechModel.allCases.filter(\.isInstalled))
    @Published var downloadPercent: [SpeechModel: Int] = [:]
    @Published var cleanupInstalled = SpokenlyCleanup.isInstalled
    @Published var cleanupPercent: Int?
    @Published var cleanupFailed = false

    func refreshInstalled() {
        installed = Set(SpeechModel.allCases.filter(\.isInstalled))
    }

    /// The model dictation can use once `model` is gone. Without one, `model` has to stay.
    func replacement(for model: SpeechModel) -> SpeechModel? {
        SpeechModel.allCases.first { $0 != model && installed.contains($0) && downloadPercent[$0] == nil }
    }
}
