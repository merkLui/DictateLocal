import AppKit
import DictateCore

/// Choosing, downloading and loading the speech models.
extension AppDelegate {
    /// A running dictation finishes with the old model. The new one only loads after the old one is
    /// gone, so the two are never in memory together.
    func selectModel(_ model: SpeechModel) {
        guard model != activeModel else { return }
        UserDefaults.standard.set(model.rawValue, forKey: Self.selectedModelKey)
        let old = transcriber
        let oldModel = activeModel
        let oldSessionDone = previousSessionDone
        activeModel = model
        transcriber = model.makeTranscriber()
        previousSessionDone = Task {
            await oldSessionDone?.value
            await old.unload()
            perfLog("MODEL: \(oldModel.rawValue) unloaded")
        }
        ModelStatus.shared.selected = model
        prepareModel()
    }

    /// Downloads a model without switching to it.
    func downloadModel(_ model: SpeechModel) {
        guard model != activeModel else {
            prepareModel()
            return
        }
        guard ModelStatus.shared.downloadPercent[model] == nil else { return }
        ModelStatus.shared.downloadPercent[model] = 0
        Task {
            do {
                try await model.download { fraction in
                    DispatchQueue.main.async {
                        ModelStatus.shared.downloadPercent[model] = Int(fraction * 100)
                    }
                }
            } catch {
                perfLog("MODEL: Failed to download \(model.rawValue): \(error.localizedDescription)")
            }
            await MainActor.run {
                ModelStatus.shared.downloadPercent[model] = nil
                ModelStatus.shared.refreshInstalled()
            }
        }
    }

    /// Deleting the selected model switches to the other one first. The files go once nothing uses them.
    func deleteModel(_ model: SpeechModel) {
        guard let replacement = ModelStatus.shared.replacement(for: model) else { return }
        if model == activeModel {
            selectModel(replacement)
        }
        ModelStatus.shared.installed.remove(model)
        let idle = previousSessionDone
        Task {
            await idle?.value
            do {
                try model.uninstall()
            } catch {
                perfLog("MODEL: Failed to delete \(model.rawValue): \(error.localizedDescription)")
            }
            await MainActor.run { ModelStatus.shared.refreshInstalled() }
        }
    }

    func prepareModel() {
        let model = activeModel
        let transcriber = self.transcriber
        let previous = previousSessionDone
        ModelStatus.shared.state = .preparing
        updateMenuBarMenu()
        let start = Date()
        Task {
            await previous?.value
            do {
                try await transcriber.prepare { fraction in
                    let percent = Int(fraction * 100)
                    DispatchQueue.main.async {
                        ModelStatus.shared.downloadPercent[model] = percent
                        guard self.activeModel == model,
                              ModelStatus.shared.state != .downloading(percent: percent) else { return }
                        ModelStatus.shared.state = .downloading(percent: percent)
                        self.updateMenuBarMenu()
                    }
                }
                perfLog("MODEL: \(model.rawValue) ready after \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
                await MainActor.run { self.finishPreparing(model, transcriber, state: .ready) }
            } catch {
                perfLog("MODEL: Failed to prepare \(model.rawValue): \(error.localizedDescription)")
                await MainActor.run { self.finishPreparing(model, transcriber, state: .failed(error.localizedDescription)) }
            }
        }
    }

    func finishPreparing(_ model: SpeechModel, _ finished: SpeechTranscriber, state: ModelStatus.State) {
        ModelStatus.shared.downloadPercent[model] = nil
        ModelStatus.shared.refreshInstalled()
        // A newer switch may already have replaced this transcriber, even with the same model.
        guard finished === transcriber else { return }
        ModelStatus.shared.state = state
        updateMenuBarMenu()
    }
}
