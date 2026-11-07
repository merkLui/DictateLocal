import DictateCore
import Testing

@Suite("Speech models")
struct SpeechModelTests {
    /// A model that was unloaded must never come back, or two models could end up in memory.
    @Test("An unloaded model refuses to load again", arguments: SpeechModel.allCases)
    func unloadIsFinal(model: SpeechModel) async {
        let transcriber = model.makeTranscriber()
        await transcriber.unload()
        await #expect(throws: CancellationError.self) {
            try await transcriber.prepare()
        }
    }
}
