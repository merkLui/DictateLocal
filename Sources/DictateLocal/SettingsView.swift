import SwiftUI
import AppKit
import AVFoundation
import ServiceManagement
import UniformTypeIdentifiers
import DictateCore

let replacementsKey = "text_replacements"
let cleanupEnabledKey = "cleanup_enabled"
let listFormattingEnabledKey = "format_lists"
let claudeCleanupEnabledKey = "claude_cleanup_enabled"
let claudeReasoningKey = "claude_reasoning"
let claudePromptKey = "claude_prompt"

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case model
    case vocabulary
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .model:       return "Model"
        case .vocabulary:  return "Vocabulary"
        case .diagnostics: return "Diagnostics"
        }
    }

    var icon: String {
        switch self {
        case .general:     return "gearshape.fill"
        case .model:       return "waveform"
        case .vocabulary:  return "character.book.closed.fill"
        case .diagnostics: return "checkmark.shield.fill"
        }
    }

    /// System Settings-style tile color.
    var tint: Color {
        switch self {
        case .general:     return .gray
        case .model:       return .purple
        case .vocabulary:  return .orange
        case .diagnostics: return .blue
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @AppStorage(replacementsKey) private var replacements: String = TextCleanup.defaultReplacementsText
    @State private var replacementRows: [ReplacementRow] = []
    @AppStorage(HotkeyPreferences.modeKey) private var hotkeyMode: String = HotkeyPreferences.mode.rawValue
    @AppStorage(MicrophoneSelection.key) private var microphoneUID: String = ""
    @State private var microphones = MicrophoneSelection.devices
    @State private var shortcut = HotkeyPreferences.shortcut
    @AppStorage("privacy_logging") private var privacyLogging: Bool = true
    @AppStorage(cleanupEnabledKey) private var cleanupEnabled = false
    @AppStorage(listFormattingEnabledKey) private var listFormattingEnabled = false
    @AppStorage(claudeCleanupEnabledKey) private var claudeCleanupEnabled = false
    @AppStorage(claudeReasoningKey) private var claudeReasoning = ClaudeCleanup.Reasoning.low.rawValue
    @State private var claudeKey = ""
    @State private var hasClaudeKey = AnthropicKey.load() != nil
    @State private var claudeConnection: ClaudeCleanup.Connection?
    @State private var isEditingPrompt = false
    @AppStorage(claudePromptKey) private var claudePrompt = ""
    @State private var isCheckingClaude = false

    @ObservedObject private var modelStatus = ModelStatus.shared
    @State private var selectedSection: SettingsSection?
    @State private var loginItemEnabled = SMAppService.mainApp.status == .enabled
    @State private var logExportMessage: String = ""
    @State private var permissions = PermissionManager.currentSnapshot()

    init(initialSection: SettingsSection = .general) {
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    SettingsIconTile(systemName: section.icon, tint: section.tint)
                }
                .badge(section == .diagnostics ? missingPermissionCount : 0)
                .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selectedSection ?? .general {
                case .general:     generalPage
                case .model:       modelPage
                case .vocabulary:  vocabularyPage
                case .diagnostics: diagnosticsPage
                }
            }
            .navigationTitle((selectedSection ?? .general).title)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, -22, for: .scrollContent)
            .contentMargins(.bottom, 16, for: .scrollContent)
            .background(BehindWindowMaterial().ignoresSafeArea())
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            refreshPermissions()
            loadReplacementRows()
            clearInitialTextFocus()
            fitWindowToPage()
        }
        .onChange(of: selectedSection) { _, _ in
            clearInitialTextFocus()
            fitWindowToPage()
        }
        .onChange(of: replacementRows.count) { _, _ in fitWindowToPage() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
            microphones = MicrophoneSelection.devices
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            microphones = MicrophoneSelection.devices
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            microphones = MicrophoneSelection.devices
        }
    }

    /// Content heights measured per page; long vocabularies scroll instead of growing further.
    private func fitWindowToPage() {
        let height: CGFloat
        switch selectedSection ?? .general {
        case .general:     height = 412
        case .model:       height = claudeCleanupEnabled ? 596 : 500
        case .vocabulary:  height = min(520, 118 + CGFloat(max(replacementRows.count, 1)) * 37)
        case .diagnostics: height = 382
        }
        (NSApp.windows.first { $0 is SettingsWindow } as? SettingsWindow)?.fitHeight(height)
    }

    // MARK: - General

    private var generalPage: some View {
        Form {
            Section {
                StatusHeader(state: statusState)
            }

            Section("Shortcut") {
                LabeledContent("Keys") {
                    ShortcutRecorder(shortcut: $shortcut)
                }
                Picker(selection: $hotkeyMode) {
                    Text("Hold or press").tag(HotkeyMode.holdOrPress.rawValue)
                    Text("Hold to talk").tag(HotkeyMode.hold.rawValue)
                    Text("Press to start and stop").tag(HotkeyMode.press.rawValue)
                } label: {
                    TitleWithInfo(title: "Activation", info: SettingInfo(
                        "How the shortcut starts and stops dictation.",
                        ("Hold or press", "Hold to talk, or tap to start and tap again to stop"),
                        ("Hold to talk", "Records only while you hold the keys"),
                        ("Press to start and stop", "Tap to start, tap again to stop")))
                }
            }

            Section {
                Picker("Microphone", selection: $microphoneUID) {
                    Text("System default").tag("")
                    ForEach(microphones) { device in
                        Text(device.name).tag(device.id)
                    }
                    if !microphoneUID.isEmpty, !microphones.contains(where: { $0.id == microphoneUID }) {
                        Text("Not connected").tag(microphoneUID)
                    }
                }
                Toggle("Open at login", isOn: launchesAtLogin)
                if case .failed = modelStatus.state {
                    LabeledContent("Speech model") {
                        Button("Download Again") {
                            (NSApp.delegate as? AppDelegate)?.prepareModel()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var launchesAtLogin: Binding<Bool> {
        Binding(
            get: { loginItemEnabled },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    perfLog("LOGIN: Could not change login item: \(error.localizedDescription)")
                }
                loginItemEnabled = SMAppService.mainApp.status == .enabled
            }
        )
    }

    private var statusState: StatusHeader.State {
        switch modelStatus.state {
        case .downloading(let percent): return .downloading(percent: percent)
        case .preparing:                return .notReady("Preparing the speech model")
        case .failed:                   return .notReady("Speech model download failed")
        case .ready:
            return missingPermissionCount > 0 ? .notReady("Needs access, see Diagnostics") : .ready
        }
    }

    private var missingPermissionCount: Int {
        [permissions.accessibility, permissions.inputMonitoring, permissions.microphone].filter { !$0 }.count
    }

    // MARK: - Speech Model

    private var modelPage: some View {
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
    private func saveClaudeKey() {
        let key = claudeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-ant-"), key.count > 30, AnthropicKey.save(key) else { return }
        hasClaudeKey = true
        claudeKey = ""
        checkClaudeConnection()
    }

    /// Only runs with a saved key; the check costs a few tokens.
    private func checkClaudeConnection() {
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

    private var claudeConnectionStatus: (text: String, color: Color)? {
        if isCheckingClaude { return ("Checking…", .secondary) }
        switch claudeConnection {
        case .connected:         return ("Connected", .green)
        case .keyRejected:       return ("Key not accepted", .red)
        case .failed(nil):       return ("Anthropic not reachable", .red)
        case .failed(let code?): return ("Anthropic error \(code)", .red)
        case nil:                return nil
        }
    }

    // MARK: - Vocabulary

    private var vocabularyPage: some View {
        Form {
            Section {
                ForEach($replacementRows) { $row in
                    HStack(spacing: 10) {
                        TextField("Misheard", text: $row.from)
                            .labelsHidden()
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        TextField("Correct", text: $row.to)
                            .labelsHidden()
                        Button {
                            replacementRows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    .textFieldStyle(.plain)
                }
            } header: {
                HStack {
                    HStack(spacing: 4) {
                        Text("Replacements")
                        InfoButton(info: SettingInfo(
                            "Fixes words the speech model keeps getting wrong, after every dictation.",
                            ("Matches", "Whole words, in any capitalization"),
                            ("Example", "Cloud Code → Claude Code")))
                    }
                    Spacer()
                    Button("Add") {
                        replacementRows.append(ReplacementRow(from: "", to: ""))
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    Button("Restore Defaults") {
                        replacements = TextCleanup.defaultReplacementsText
                        loadReplacementRows()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: replacementRows) { _, rows in
            replacements = rows
                .filter { !$0.from.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { "\($0.from) -> \($0.to)" }
                .joined(separator: "\n")
        }
    }

    private func loadReplacementRows() {
        replacementRows = TextCleanup.parseReplacements(replacements).map {
            ReplacementRow(from: $0.from, to: $0.to)
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsPage: some View {
        Form {
            Section("Permissions") {
                PermissionRow(title: "Accessibility", purpose: "Lets DictateLocal type and paste text into other apps.",
                              isGranted: permissions.accessibility) {
                    PermissionManager.requestAccessibilityPermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refreshPermissions() }
                }
                PermissionRow(title: "Input Monitoring", purpose: "Lets DictateLocal notice the shortcut in every app.",
                              isGranted: permissions.inputMonitoring) {
                    PermissionManager.requestInputMonitoringPermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refreshPermissions() }
                }
                PermissionRow(title: "Microphone", purpose: "Lets DictateLocal record your voice. The audio never leaves this Mac.",
                              isGranted: permissions.microphone) {
                    PermissionManager.requestMicrophonePermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refreshPermissions() }
                }
            }

            Section("Log") {
                Toggle(isOn: $privacyLogging) {
                    TitleWithInfo(title: "Hide dictated text in log", info: SettingInfo(
                        "The log records timings and errors for troubleshooting.",
                        ("On", "Your dictated text is left out"),
                        ("Off", "Your dictated text is written to the log"),
                        ("Stored", "Only on this Mac, until you export it")))
                }

                HStack(spacing: 8) {
                    if !logExportMessage.isEmpty {
                        Text(logExportMessage)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear", role: .destructive) { clearLogs() }
                    Button("Export…") { exportLogs() }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func exportLogs() {
        let savePanel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        savePanel.nameFieldStringValue = "DictateLocal-Logs-\(formatter.string(from: Date())).log"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "log") ?? .plainText]
        savePanel.canCreateDirectories = true
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do { try AppLogger.exportLog(to: url); logExportMessage = "Log exported." }
            catch { logExportMessage = "Export failed: \(error.localizedDescription)" }
        }
    }

    private func clearLogs() {
        AppLogger.clearLog()
        logExportMessage = "Log cleared."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { logExportMessage = "" }
    }

    private func refreshPermissions() {
        permissions = PermissionManager.currentSnapshot()
    }
}

// MARK: - Window Background

/// Standard material for the content layer: the desktop shows through softly and text stays legible.
private struct BehindWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Status Header

private struct StatusHeader: View {
    enum State: Equatable {
        case ready
        case downloading(percent: Int)
        case notReady(String)
    }

    let state: State

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "DictateLocal"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(appName)
                    .font(.title3.weight(.semibold))
                status
                    .font(.callout)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .ready:
            statusLine(color: .green, text: "Ready")
        case .notReady(let text):
            statusLine(color: .orange, text: text)
        case .downloading(let percent):
            HStack(spacing: 8) {
                ProgressView(value: Double(percent), total: 100)
                    .frame(width: 120)
                Text("Downloading speech model, \(percent) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusLine(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

private struct KeyCaps: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 9)
                    .frame(minWidth: 30, minHeight: 26)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}

// MARK: - Speech Model Row

private struct SpeechModelRow: View {
    let model: SpeechModel
    let isSelected: Bool
    let isInstalled: Bool
    let downloadPercent: Int?
    /// What takes over if this model is deleted; nil keeps the last usable model from being deleted.
    let replacement: SpeechModel?

    @State private var isConfirmingDelete = false

    private var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    private var isSelectable: Bool { isInstalled && downloadPercent == nil }

    var body: some View {
        HStack(spacing: 12) {
            // A tap gesture instead of a button, so the info button inside stays its own control.
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .opacity(isInstalled || isSelected ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(model.title)
                            .foregroundStyle(isSelectable || isSelected ? .primary : .secondary)
                        InfoButton(info: model.info)
                    }
                    if let downloadPercent {
                        Text(InstallProgress.status(percent: downloadPercent, finishing: "Preparing…"))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelectable { delegate?.selectModel(model) }
            }
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction {
                if isSelectable { delegate?.selectModel(model) }
            }

            Spacer(minLength: 8)

            if let downloadPercent {
                InstallProgress(percent: downloadPercent)
            } else if !isInstalled {
                iconButton("icloud.and.arrow.down", label: "Download") {
                    delegate?.downloadModel(model)
                }
                .help("Download")
            } else {
                iconButton("trash", label: "Delete") {
                    isConfirmingDelete = true
                }
                .disabled(replacement == nil)
                .help(replacement == nil ? "Download another model first" : "Delete")
            }
        }
        .padding(.vertical, 2)
        .confirmationDialog("Delete \(model.title)?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { delegate?.deleteModel(model) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if isSelected, let replacement {
                Text("DictateLocal switches to \(replacement.title). You can download this model again anytime.")
            } else {
                Text("You can download this model again anytime.")
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Install Progress

/// Spins until there is a real percentage, and again for the work after the download.
private struct InstallProgress: View {
    let percent: Int

    static func status(percent: Int, finishing: String) -> String {
        switch percent {
        case 0:   return "Starting download…"
        case 100: return finishing
        default:  return "Downloading, \(percent) %"
        }
    }

    var body: some View {
        Group {
            if percent == 0 || percent == 100 {
                ProgressView()
            } else {
                ProgressView(value: Double(percent), total: 100)
                    .progressViewStyle(.circular)
            }
        }
        .controlSize(.small)
        .frame(width: 28, height: 28)
    }
}

// MARK: - Subsection Header

/// A smaller header for a group within a section, aligned with the edge of its box.
private struct SubsectionHeader: View {
    let title: String

    /// How far the groups under a section move in.
    static let indent: CGFloat = 20

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            // Headers sit 10 pt inside their box; this one starts at the box edge.
            .padding(.leading, -10)
    }
}

private extension View {
    /// One group of a page built from several forms.
    func subform(indented: Bool = false) -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, indented ? SubsectionHeader.indent : 0)
    }
}

// MARK: - Info Button

/// What an info button explains: one sentence, then short facts.
struct SettingInfo {
    let summary: String
    let facts: [(label: String, value: String)]

    init(_ summary: String, _ facts: (label: String, value: String)...) {
        self.summary = summary
        self.facts = facts
    }
}

extension SpeechModel {
    var info: SettingInfo {
        switch self {
        case .nemotron:
            return SettingInfo("Streaming: types at the cursor while you speak.",
                               ("Delay", "About 2 s behind your voice"),
                               ("Disk", "590 MB"),
                               ("Memory", "About 110 MB"))
        case .parakeetUltra:
            return SettingInfo("Inserts the whole text once when you stop.",
                               ("Wait", "Under 1 s after you stop"),
                               ("Disk", "About 600 MB"),
                               ("Memory", "About 150 MB"))
        }
    }
}

/// A row title with an info button right after it.
private struct TitleWithInfo: View {
    let title: String
    let info: SettingInfo

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            InfoButton(info: info)
        }
    }
}

private struct InfoButton: View {
    let info: SettingInfo
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Info")
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(info.summary)
                    .fixedSize(horizontal: false, vertical: true)
                if !info.facts.isEmpty {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
                        ForEach(info.facts.indices, id: \.self) { index in
                            GridRow {
                                Text(info.facts[index].label)
                                    .foregroundStyle(.secondary)
                                Text(info.facts[index].value)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.callout)
                }
            }
            .frame(width: 300, alignment: .leading)
            .padding(14)
        }
    }
}

// MARK: - Prompt Editor

private struct PromptEditor: View {
    @Binding var prompt: String
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Haiku Prompt")
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 560, height: 360)
            HStack {
                Button("Reset to Default") { text = ClaudeCleanup.defaultPrompt }
                    .disabled(text == ClaudeCleanup.defaultPrompt)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Storing nothing for the default lets later app versions improve it.
                    prompt = trimmed == ClaudeCleanup.defaultPrompt ? "" : trimmed
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .onAppear { text = prompt.isEmpty ? ClaudeCleanup.defaultPrompt : prompt }
    }
}

// MARK: - Cleanup Row

private struct CleanupRow: View {
    @Binding var isEnabled: Bool
    let isInstalled: Bool
    let percent: Int?
    let failed: Bool

    @State private var isConfirmingDelete = false

    private var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    var body: some View {
        // A plain row instead of LabeledContent, which pins the title to the top next to the taller trash button.
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TitleWithInfo(title: "Spokenly Cleanup", info: SettingInfo(
                    "Removes filler words and adds punctuation, on this Mac.",
                    ("Misheard words", "Not fixed"),
                    ("Disk", "331 MB"),
                    ("Memory", "About 450 MB while in use"),
                    ("Unloads", "After 5 idle minutes")))
                if let status {
                    Text(status)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                if let percent {
                    InstallProgress(percent: percent)
                } else if isInstalled {
                    Button {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }

                Toggle("Spokenly Cleanup", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(percent != nil)
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            delegate?.cleanupToggled(enabled)
        }
        .confirmationDialog("Delete Spokenly Cleanup?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                isEnabled = false
                delegate?.deleteCleanupModel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can download it again anytime.")
        }
    }

    private var status: String? {
        if let percent { return InstallProgress.status(percent: percent, finishing: "Optimizing for this Mac…") }
        return failed ? "Download failed" : nil
    }
}

// MARK: - Shortcut Recorder

private struct ShortcutRecorder: View {
    @Binding var shortcut: HotkeyShortcut
    @State private var isRecording = false
    @State private var message: String?

    private var manager: HotkeyManager? {
        (NSApp.delegate as? AppDelegate)?.hotkeyManager
    }

    var body: some View {
        HStack(spacing: 10) {
            if let message {
                Text(message)
                    .foregroundStyle(.orange)
            }
            if isRecording {
                Text("Press keys…")
                    .foregroundStyle(.secondary)
                Button("Cancel") { manager?.cancelRecording() }
            } else {
                KeyCaps(labels: shortcut.keys.map(\.label))
                Button("Change") { record() }
            }
        }
    }

    private func record() {
        guard let manager, manager.canListen else {
            message = "Needs Input Monitoring"
            return
        }
        message = nil
        isRecording = true
        manager.startRecording { result in
            isRecording = false
            switch result {
            case .recorded(let recorded):
                shortcut = recorded
                HotkeyPreferences.shortcut = recorded
            case .invalid(.tooManyKeys):
                message = "Use up to three keys"
            case .invalid(.needsModifier):
                message = "Add ⌘, ⌥, ⌃ or fn"
            case .canceled:
                break
            }
        }
    }
}

// MARK: - Replacement Row

private struct ReplacementRow: Identifiable, Equatable {
    let id = UUID()
    var from: String
    var to: String
}

// MARK: - Sidebar Icon

private struct SettingsIconTile: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.gradient))
    }
}

// MARK: - Rows

private struct PermissionRow: View {
    let title: String
    let purpose: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent {
            if isGranted {
                Text("Granted")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Text("Not granted")
                        .foregroundStyle(.orange)
                    Button("Grant Access…", action: action)
                }
            }
        } label: {
            Label {
                TitleWithInfo(title: title, info: SettingInfo(purpose))
            } icon: {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(isGranted ? .green : .orange)
            }
        }
    }
}

private func clearInitialTextFocus() {
    for delay in [0.0, 0.05, 0.15, 0.4] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}
