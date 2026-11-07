import AppKit
import DictateCore

/// Settings and lifecycle of the text cleanup: Spokenly on the Mac or Claude online.
extension AppDelegate {
    var usesCleanup: Bool {
        UserDefaults.standard.bool(forKey: cleanupEnabledKey) && SpokenlyCleanup.isInstalled
    }

    /// Claude formats lists itself; the rules only step in when it gave no answer.
    var usesListFormatting: Bool {
        UserDefaults.standard.bool(forKey: listFormattingEnabledKey) || usesClaudeCleanup
    }

    var usesClaudeCleanup: Bool {
        UserDefaults.standard.bool(forKey: claudeCleanupEnabledKey)
    }

    /// An empty setting means the built-in prompt.
    var claudePrompt: String {
        let custom = UserDefaults.standard.string(forKey: claudePromptKey) ?? ""
        return custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ClaudeCleanup.defaultPrompt : custom
    }

    var claudeReasoning: ClaudeCleanup.Reasoning {
        UserDefaults.standard.string(forKey: claudeReasoningKey).flatMap(ClaudeCleanup.Reasoning.init(rawValue:)) ?? .low
    }

    /// A key handed over with `defaults write com.luismerk.DictateLocal anthropic_api_key …`
    /// moves into the key file, so it does not stay in the settings file.
    func importAnthropicKey() {
        let defaultsKey = "anthropic_api_key"
        guard let key = UserDefaults.standard.string(forKey: defaultsKey) else { return }
        if AnthropicKey.save(key) {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            perfLog("CLEANUP: Imported Anthropic API key")
        }
    }

    /// Turning cleanup on for the first time also installs the model.
    func cleanupToggled(_ enabled: Bool) {
        guard enabled else {
            Task { await cleanup.unload() }
            return
        }
        guard !SpokenlyCleanup.isInstalled, ModelStatus.shared.cleanupPercent == nil else { return }
        ModelStatus.shared.cleanupPercent = 0
        ModelStatus.shared.cleanupFailed = false
        Task {
            do {
                try await cleanup.install { fraction in
                    DispatchQueue.main.async { ModelStatus.shared.cleanupPercent = Int(fraction * 100) }
                }
            } catch {
                perfLog("CLEANUP: Install failed: \(error.localizedDescription)")
                await MainActor.run {
                    UserDefaults.standard.set(false, forKey: cleanupEnabledKey)
                    ModelStatus.shared.cleanupFailed = true
                }
            }
            await MainActor.run {
                ModelStatus.shared.cleanupPercent = nil
                ModelStatus.shared.cleanupInstalled = SpokenlyCleanup.isInstalled
            }
        }
    }

    func deleteCleanupModel() {
        UserDefaults.standard.set(false, forKey: cleanupEnabledKey)
        ModelStatus.shared.cleanupInstalled = false
        Task {
            do {
                try await cleanup.uninstall()
            } catch {
                perfLog("CLEANUP: Delete failed: \(error.localizedDescription)")
            }
            await MainActor.run { ModelStatus.shared.cleanupInstalled = SpokenlyCleanup.isInstalled }
        }
    }

    func currentReplacements() -> [TextCleanup.Replacement] {
        let stored = UserDefaults.standard.string(forKey: replacementsKey) ?? TextCleanup.defaultReplacementsText
        return TextCleanup.parseReplacements(stored)
    }
}
