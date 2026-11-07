import Cocoa
import SwiftUI
import DictateCore
import ServiceManagement

enum RecordMode {
    case pushToTalk
    case toggle
}

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

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

    // Core Managers
    var hotkeyManager: HotkeyManager!
    var recorderManager: RecorderManager!
    var textIntegrator: TextIntegrator!
    private(set) var activeModel = AppDelegate.savedModel
    private(set) lazy var transcriber: SpeechTranscriber = activeModel.makeTranscriber()
    private let cleanup = SpokenlyCleanup()
    private var session: DictationSession?
    private var previousSessionDone: Task<Void, Never>?

    // Windows
    var hudWindow: HUDWindow?
    var settingsWindow: SettingsWindow?

    // App State
    var isRecording = false {
        didSet { if !isRecording { isProcessing = false } }
    }
    /// True between key release and paste, while the final text is produced.
    private(set) var isProcessing = false
    /// The microphone is live and a new press should control this dictation rather than start one.
    var isCapturingAudio: Bool { isRecording && !isProcessing }
    var currentRecordMode: RecordMode = .pushToTalk

    // Ephemeral last dictation RAM backup (100% private, clears on app quit)
    var lastDictationText: String? {
        didSet {
            updateMenuBarMenu()
            scheduleDictationClear()
        }
    }

    private var dictationClearTimer: Timer?

    private func scheduleDictationClear() {
        dictationClearTimer?.invalidate()
        guard lastDictationText != nil else { return }
        // Clear RAM backup after 5 minutes (300 seconds)
        dictationClearTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            self?.lastDictationText = nil
            perfLog("AX: Cleared ephemeral dictation RAM backup after 5 minutes timeout")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.recorderManager = RecorderManager()
        self.textIntegrator = TextIntegrator()

        // Setup Menu Bar Status Item
        setupMenuBar()

        // Setup global activation key listener.
        setupHotkey()

        // Setup hidden standard Edit menu to enable Cmd+A, Cmd+C, Cmd+V, Cmd+Z
        setupEditMenu()

        // Pre-create HUD window (initially hidden)
        self.hudWindow = HUDWindow(appDelegate: self)

        // The model stays loaded: it costs little memory while idle, and reloading would delay dictation.
        prepareModel()
        // An install that a quit interrupted starts over, because the switch still says on.
        cleanupToggled(UserDefaults.standard.bool(forKey: cleanupEnabledKey))
        importAnthropicKey()
        logPermissionStatus()
        enableLoginItemOnFirstLaunch()

        // Opens a settings page directly, for example: --settings=vocabulary
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--settings") }) {
            let name = argument.components(separatedBy: "=").last ?? ""
            openSettings(section: SettingsSection(rawValue: name) ?? .general)
        }
    }

    /// Dictation should simply be there after a restart. Settings can turn this off for good.
    private func enableLoginItemOnFirstLaunch() {
        let key = "login_item_configured"
        guard !UserDefaults.standard.bool(forKey: key),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            perfLog("LOGIN: Could not add login item: \(error.localizedDescription)")
        }
    }

    private static let selectedModelKey = "speech_model"

    static var savedModel: SpeechModel {
        UserDefaults.standard.string(forKey: selectedModelKey).flatMap(SpeechModel.init(rawValue:)) ?? .nemotron
    }

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

    // MARK: - Text Cleanup

    private var usesCleanup: Bool {
        UserDefaults.standard.bool(forKey: cleanupEnabledKey) && SpokenlyCleanup.isInstalled
    }

    /// Claude formats lists itself; the rules only step in when it gave no answer.
    private var usesListFormatting: Bool {
        UserDefaults.standard.bool(forKey: listFormattingEnabledKey) || usesClaudeCleanup
    }

    private var usesClaudeCleanup: Bool {
        UserDefaults.standard.bool(forKey: claudeCleanupEnabledKey)
    }

    /// An empty setting means the built-in prompt.
    private var claudePrompt: String {
        let custom = UserDefaults.standard.string(forKey: claudePromptKey) ?? ""
        return custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ClaudeCleanup.defaultPrompt : custom
    }

    private var claudeReasoning: ClaudeCleanup.Reasoning {
        UserDefaults.standard.string(forKey: claudeReasoningKey).flatMap(ClaudeCleanup.Reasoning.init(rawValue:)) ?? .low
    }

    /// A key handed over with `defaults write com.luismerk.DictateLocal anthropic_api_key …`
    /// moves into the key file, so it does not stay in the settings file.
    private func importAnthropicKey() {
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

    private func finishPreparing(_ model: SpeechModel, _ finished: SpeechTranscriber, state: ModelStatus.State) {
        ModelStatus.shared.downloadPercent[model] = nil
        ModelStatus.shared.refreshInstalled()
        // A newer switch may already have replaced this transcriber, even with the same model.
        guard finished === transcriber else { return }
        ModelStatus.shared.state = state
        updateMenuBarMenu()
    }

    private func setupEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    private func logPermissionStatus() {
        let snapshot = PermissionManager.currentSnapshot()
        perfLog("PERMISSIONS: accessibility=\(snapshot.accessibility), inputMonitoring=\(snapshot.inputMonitoring), microphone=\(snapshot.microphone)")
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyStatusIcon(accessibilityDescription: "DictateLocal")

        let menu = NSMenu()
        statusItem.menu = menu
        updateMenuBarMenu()
    }

    private func updateMenuBarMenu() {
        guard let menu = statusItem.menu else { return }

        menu.removeAllItems()

        if let status = modelStatusMenuTitle {
            let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Custom SwiftUI-based Last Dictation menu item card (ephemeral, single-use RAM backup)
        if let text = lastDictationText, !text.isEmpty {
            let dictationItem = NSMenuItem()
            let hostingView = NSHostingView(rootView: LastDictationMenuItemView(text: text, onCopy: { [weak self] in
                guard let self = self else { return }

                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                perfLog("AX: User copied last dictation manually from menu bar")

                NSSound(named: "Glass")?.play()
                self.lastDictationText = nil // Clear RAM backup so it instantly disappears!
                self.statusItem.menu?.cancelTracking()
            }))

            hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 26)
            dictationItem.view = hostingView
            menu.addItem(dictationItem)

            menu.addItem(NSMenuItem.separator())
        }

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings as () -> Void), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
    }

    private var modelStatusMenuTitle: String? {
        switch ModelStatus.shared.state {
        case .preparing:                  return "Preparing speech model…"
        case .downloading(let percent):   return "Downloading speech model: \(percent) %"
        case .ready:                      return nil
        case .failed:                     return "Speech model download failed"
        }
    }

    private func setupHotkey() {
        self.hotkeyManager = HotkeyManager { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .pressed:
                    self.startRecordingFlow()
                case .released:
                    self.stopRecordingFlow()
                case .canceled:
                    self.cancelRecordingFlow()
                }
            }
        }
    }

    // MARK: - Recording Actions

    func startRecordingFlow() {
        guard !isRecording else { return }

        isRecording = true
        currentRecordMode = .pushToTalk // Defaults to Hold, HotkeyManager updates this if it's a Tap

        // Show Floating HUD (waveform state) immediately on the main thread
        hudWindow?.showHUD(mode: currentRecordMode)

        applyStatusIcon(accessibilityDescription: "Dictating")

        let recordingID = AppLogger.shortID(prefix: "rec")
        diagnosticLog("PIPELINE", "recordingStarted", fields: ["recordingId": recordingID])

        textIntegrator.captureActiveApp(typesLive: activeModel.typesLive)

        if usesCleanup {
            Task.detached(priority: .medium) { [cleanup] in await cleanup.prepare() }
        }

        let activeSession = WeakBox<DictationSession>()
        let session = DictationSession(transcriber: transcriber, after: previousSessionDone) { [weak self] partial in
            guard let self = self else { return }
            let replacements = self.currentReplacements()
            let cleaned = TextCleanup.clean(partial, replacements: replacements)
            let stable = LiveText.stablePrefix(of: cleaned, holdBackWords: LiveText.holdBackWords(for: replacements))
            DispatchQueue.main.async {
                // A partial from a canceled session must not reach the next one.
                guard self.isCapturingAudio, self.session === activeSession.value else { return }
                self.textIntegrator.updateLiveText(stable)
            }
        }
        activeSession.value = session
        self.session = session
        previousSessionDone = session.completion

        recorderManager.startRecording(recordingID: recordingID, onAudio: { buffer in
            session.append(buffer)
        }, onNoAudio: { [weak self] in
            perfLog("AUDIO: No microphone audio received after restart; aborting recording")
            DispatchQueue.main.async {
                self?.abortDictationWithError(title: "Kein Audio")
            }
        }) { [weak self] error in
            if let error = error {
                perfLog("AUDIO: Dictation start failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.abortDictationWithError(title: "Dictation start failed")
                }
            }
        }
    }

    func stopRecordingFlow() {
        guard isRecording, !isProcessing else { return }
        isProcessing = true
        textIntegrator.stopWaitingForTarget()

        // Dictation can end in another app than it started in. The text then goes there, whole.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != textIntegrator.targetAppPID {
            textIntegrator.captureActiveApp(typesLive: false)
        }

        resetMenuBarIcon()

        // The last word is often still being spoken while the key goes up.
        recorderManager.stopRecording(after: 0.4) { [weak self] in
            self?.finishRecordingFlow()
        }
    }

    private func finishRecordingFlow() {
        guard recorderManager.hasCapturedAudio, let session = session else {
            perfLog("PIPELINE: No microphone audio captured.")
            abortDictationWithError(title: "Audio recording empty")
            return
        }

        hudWindow?.showProcessing()

        let pipelineStart = Date()
        let cleansUp = usesCleanup
        let cleanup = self.cleanup
        let claudeKey = usesClaudeCleanup ? AnthropicKey.load() : nil
        let reasoning = claudeReasoning
        let prompt = claudePrompt
        let singleLine = textIntegrator.targetIsSingleLine
        Task { [weak self] in
            do {
                let transcription = try await session.finish()
                // The dictation is on screen right away, and the improved version follows.
                await MainActor.run {
                    guard let self, self.session === session else { return }
                    self.typeRemainingWords(of: transcription)
                }
                var polished = transcription
                var formatted = false
                let words = Double(transcription.split(separator: " ").count)
                if let claudeKey {
                    let start = Date()
                    if let answer = await ClaudeCleanup.polish(transcription, key: claudeKey, prompt: prompt, reasoning: reasoning,
                                                               singleLine: singleLine, timeout: reasoning.timeout + words * 0.01) {
                        polished = answer
                        formatted = true
                    }
                    perfLog(String(format: "CLEANUP: Claude %@ (%@) after %.2fs", formatted ? "used" : "skipped", reasoning.rawValue, Date().timeIntervalSince(start)))
                } else if cleansUp {
                    polished = await cleanup.polish(transcription, timeout: 5 + words * 0.03)
                }
                let text = polished
                let listsDone = formatted
                await MainActor.run {
                    // The user may have canceled during cleanup.
                    guard let self, self.session === session else { return }
                    self.deliver(text, transcription: transcription, listsDone: listsDone, pipelineStart: pipelineStart)
                }
            } catch {
                perfLog("PIPELINE: Transcription failed: \(error.localizedDescription)")
                await MainActor.run {
                    guard let self, self.session === session else { return }
                    self.abortDictationWithError(title: "Speech recognition failed")
                }
            }
        }
    }

    func cancelRecordingFlow() {
        isRecording = false
        session?.cancel()
        session = nil
        recorderManager.cancelRecording()
        textIntegrator.discardLiveText()
        hudWindow?.hideHUD()
        resetMenuBarIcon()
    }

    private func resetMenuBarIcon() {
        applyStatusIcon(accessibilityDescription: "DictateLocal")
    }

    private func abortDictationWithError(title: String) {
        isRecording = false
        session?.cancel()
        session = nil
        recorderManager.cancelRecording()
        resetMenuBarIcon()
        // Show compact error toast in HUD instead of large NSAlert
        hudWindow?.showErrorToast(title: title, message: "")
    }

    private func currentReplacements() -> [TextCleanup.Replacement] {
        let stored = UserDefaults.standard.string(forKey: replacementsKey) ?? TextCleanup.defaultReplacementsText
        return TextCleanup.parseReplacements(stored)
    }

    // MARK: - Pipeline Processing

    private func typeRemainingWords(of transcription: String) {
        textIntegrator.updateLiveText(TextCleanup.clean(transcription, replacements: currentReplacements()))
    }

    /// `listsDone` means Claude already formatted the lists, which the rules must not redo.
    private func deliver(_ polished: String, transcription: String, listsDone: Bool, pipelineStart: Date) {
        let delivering = session
        let replacements = currentReplacements()
        var finalText = TextCleanup.clean(polished, replacements: replacements)
        if usesListFormatting && !listsDone && !textIntegrator.targetIsSingleLine {
            finalText = ListFormatter.format(finalText)
        }
        let plainText = TextCleanup.clean(transcription, replacements: replacements)
        guard textIntegrator.isTypingLive, finalText != plainText else {
            finish(finalText, pipelineStart: pipelineStart)
            return
        }
        // Where typed text cannot be verified, it simply stays as dictated.
        textIntegrator.whenRewritable(to: finalText) { [weak self] rewritable in
            guard let self, self.session === delivering else { return }
            self.finish(rewritable ? finalText : plainText, pipelineStart: pipelineStart)
        }
    }

    private func finish(_ finalText: String, pipelineStart: Date) {
        session = nil
        diagnosticLog(
            "PIPELINE",
            "transcribed",
            fields: [
                "durationSeconds": String(format: "%.3f", Date().timeIntervalSince(pipelineStart)),
                "outputChars": finalText.count
            ],
            privateFields: ["result": finalText]
        )

        isRecording = false

        // Text already typed at the cursor is brought to its final form.
        let pastesLineBreaks = textIntegrator.isTypingLive && finalText.contains("\n")
        if textIntegrator.isTypingLive, !pastesLineBreaks {
            textIntegrator.updateLiveText(finalText)
        }

        guard !finalText.isEmpty else {
            hudWindow?.showErrorToast(title: "No text detected", message: "")
            return
        }

        lastDictationText = finalText // Ephemeral RAM backup
        textIntegrator.setText(finalText)

        if pastesLineBreaks {
            // Pasted line breaks never send a chat message, unlike a typed Return.
            textIntegrator.finishLiveTextByPasting(
                finalText,
                onSuccess: { [weak self] in self?.hudWindow?.hideHUD() },
                onFailure: { [weak self] in self?.hudWindow?.showClipboardCapsule(text: finalText) }
            )
            return
        }

        if textIntegrator.isTypingLive {
            textIntegrator.whenTypingFinished { [weak self] in
                guard let self else { return }
                if self.textIntegrator.lostLiveTarget {
                    self.hudWindow?.showClipboardCapsule(text: finalText)
                } else {
                    self.hudWindow?.hideHUD()
                }
            }
            return
        }

        // The target was lost mid-dictation or takes a password, so the text is only offered for copying.
        if textIntegrator.lostLiveTarget || textIntegrator.targetIsSecure {
            hudWindow?.showClipboardCapsule(text: finalText)
            return
        }

        let result = textIntegrator.finalizeIntegration(
            onSuccess: { [weak self] in
                self?.hudWindow?.hideHUD()
            },
            onFailure: { [weak self] in
                self?.hudWindow?.showClipboardCapsule(text: self?.textIntegrator.accumulatedText ?? "")
            }
        )
        if result == .failed {
            hudWindow?.showClipboardCapsule(text: textIntegrator.accumulatedText)
        }
    }

    // MARK: - Menu Selectors

    @objc func openSettings() {
        openSettings(section: .general)
    }

    private func openSettings(section: SettingsSection) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(initialSection: section)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func applyStatusIcon(accessibilityDescription: String) {
        if let button = statusItem.button {
            button.image = Self.makeWaveBarStatusIcon(accessibilityDescription: accessibilityDescription)
            button.imagePosition = .imageOnly
            button.contentTintColor = nil
            button.alphaValue = 1
            button.isEnabled = true
        }
    }

    private static func makeWaveBarStatusIcon(accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.black.setFill()

        let bars: [(x: CGFloat, height: CGFloat)] = [
            (1.2, 13.5),
            (4.9, 8.5),
            (8.6, 15.5),
            (12.3, 8.5),
            (16.0, 13.5)
        ]

        for bar in bars {
            let width: CGFloat = 2.2
            let rect = NSRect(
                x: bar.x,
                y: (18 - bar.height) / 2,
                width: width,
                height: bar.height
            )
            NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
