import DictateCore
import SwiftUI

extension SettingsView {
    var modelPage: some View {
        // One form per group, because a form cannot indent its grey boxes.
        ScrollView {
            VStack(spacing: 0) {
                Form {
            Section {
                ForEach(SpeechModel.allCases) { model in
                    SpeechModelRow(
                        model: model,
                        isSelected: modelStatus.selected == model,
                        isInstalled: modelStatus.installed.contains(model),
                        downloadPercent: modelStatus.downloadPercent[model],
                        replacement: modelStatus.replacement(for: model)
                    )
                }
            } header: {
                Text("Speech to Text")
            }
                }
                .subform()

                Form {
            Section {
                CleanupRow(
                    isEnabled: $cleanupEnabled,
                    isInstalled: modelStatus.cleanupInstalled,
                    percent: modelStatus.cleanupPercent,
                    failed: modelStatus.cleanupFailed
                )
                // With Claude on, it formats the lists itself.
                if !claudeCleanupEnabled {
                    Toggle(isOn: $listFormattingEnabled) {
                        TitleWithInfo(title: "Format lists", info: SettingInfo(
                            "Turns dictated lists into bullet points.",
                            ("Method", "Fixed rules, no model"),
                            ("Single-line fields", "Never get lists")))
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Improve Text")
                        .padding(.leading, -SubsectionHeader.indent)
                    SubsectionHeader(title: "On Device")
                }
            }
                }
                .subform(indented: true)

                Form {
            Section {
                Toggle(isOn: $claudeCleanupEnabled) {
                    TitleWithInfo(title: "Claude Haiku", info: SettingInfo(
                        "Cleans up each dictation in the cloud: fixes misheard words, removes filler words and formats lists.",
                        ("Delay", "About 1 s after you stop"),
                        ("Cost", "About 0.01 cents per dictation"),
                        ("Privacy", "Dictations are sent to Anthropic"),
                        ("Offline", "Text stays as dictated")))
                }
                if claudeCleanupEnabled {
                    LabeledContent {
                        HStack(spacing: 12) {
                            SecureField("API key", text: $claudeKey, prompt: Text(hasClaudeKey ? "Saved" : "sk-ant-…"))
                                .labelsHidden()
                                .onSubmit(saveClaudeKey)
                            if hasClaudeKey {
                                Button {
                                    AnthropicKey.delete()
                                    hasClaudeKey = false
                                    claudeConnection = nil
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                        .font(.title3)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .help("Remove")
                            }
                        }
                    } label: {
                        TitleWithInfo(title: "API key", info: SettingInfo(
                            "Your Anthropic API key. Keys from other providers do not work.",
                            ("Get one", "console.anthropic.com"),
                            ("Starts with", "sk-ant-"),
                            ("Stored", "In a file only you can read")))
                        // A live status, not a description.
                        if let status = claudeConnectionStatus {
                            Text(status.text).foregroundStyle(status.color)
                        }
                    }
                    .onChange(of: claudeKey) { _, _ in saveClaudeKey() }
                    Picker(selection: $claudeReasoning) {
                        Text("Off").tag(ClaudeCleanup.Reasoning.off.rawValue)
                        Text("Low").tag(ClaudeCleanup.Reasoning.low.rawValue)
                        Text("Medium").tag(ClaudeCleanup.Reasoning.medium.rawValue)
                        Text("High").tag(ClaudeCleanup.Reasoning.high.rawValue)
                    } label: {
                        TitleWithInfo(title: "Reasoning", info: SettingInfo(
                            "How long Claude thinks before answering.",
                            ("Off", "Fastest, sometimes translates English"),
                            ("Low", "About 1 s, recommended"),
                            ("Medium", "About 1 s, sometimes longer"),
                            ("High", "Most careful, can take 10 s")))
                    }
                    LabeledContent {
                        HStack(spacing: 12) {
                            Text(claudePrompt.isEmpty ? "Default" : "Custom")
                                .foregroundStyle(.secondary)
                            Button("Edit…") { isEditingPrompt = true }
                        }
                    } label: {
                        TitleWithInfo(title: "Prompt", info: SettingInfo(
                            "The instructions Claude follows for every dictation.",
                            ("Default", "Tested on 109 real and sample dictations"),
                            ("Reset", "Edit… > Reset to Default")))
                    }
                }
            } header: {
                SubsectionHeader(title: "Cloud")
            }
                }
                .subform(indented: true)
                // Both groups belong to Improve Text, so they sit closer together.
                .padding(.top, -22)
            }
        }
        .sheet(isPresented: $isEditingPrompt) {
            PromptEditor(prompt: $claudePrompt)
        }
        // Spokenly and Claude both clean the whole text, so only one of them runs.
        .onChange(of: claudeCleanupEnabled) { _, enabled in
            if enabled { cleanupEnabled = false }
            checkClaudeConnection()
            fitWindowToPage()
        }
        .onAppear(perform: checkClaudeConnection)
        .onChange(of: cleanupEnabled) { _, enabled in
            if enabled { claudeCleanupEnabled = false }
        }
    }

    /// A pasted key is saved right away; the field stays empty afterwards.
    func saveClaudeKey() {
        let key = claudeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-ant-"), key.count > 30, AnthropicKey.save(key) else { return }
        hasClaudeKey = true
        claudeKey = ""
        checkClaudeConnection()
    }

    /// Only runs with a saved key; the check costs a few tokens.
    func checkClaudeConnection() {
        guard claudeCleanupEnabled, let key = AnthropicKey.load() else {
            claudeConnection = nil
            return
        }
        isCheckingClaude = true
        Task {
            claudeConnection = await ClaudeCleanup.checkConnection(key: key)
            isCheckingClaude = false
        }
    }

    var claudeConnectionStatus: (text: String, color: Color)? {
        if isCheckingClaude { return ("Checking…", .secondary) }
        switch claudeConnection {
        case .connected:         return ("Connected", .green)
        case .keyRejected:       return ("Key not accepted", .red)
        case .failed(nil):       return ("Anthropic not reachable", .red)
        case .failed(let code?): return ("Anthropic error \(code)", .red)
        case nil:                return nil
        }
    }
}
