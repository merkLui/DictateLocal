import Cocoa
import SwiftUI
import DictateCore
import ServiceManagement

enum RecordMode {
    case pushToTalk
    case toggle
}

final class WeakBox<Value: AnyObject> {
    weak var value: Value?
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

    // Core Managers
    var hotkeyManager: HotkeyManager!
    var recorderManager: RecorderManager!
    var textIntegrator: TextIntegrator!
    var activeModel = AppDelegate.savedModel
    lazy var transcriber: SpeechTranscriber = activeModel.makeTranscriber()
    let cleanup = SpokenlyCleanup()
    var session: DictationSession?
    var previousSessionDone: Task<Void, Never>?

    // Windows
    var hudWindow: HUDWindow?
    var settingsWindow: SettingsWindow?

    // App State
    var isRecording = false {
        didSet { if !isRecording { isProcessing = false } }
    }
    /// True between key release and paste, while the final text is produced.
    var isProcessing = false
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

    var dictationClearTimer: Timer?

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
    func enableLoginItemOnFirstLaunch() {
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

    static let selectedModelKey = "speech_model"

    static var savedModel: SpeechModel {
        UserDefaults.standard.string(forKey: selectedModelKey).flatMap(SpeechModel.init(rawValue:)) ?? .nemotron
    }

    func logPermissionStatus() {
        let snapshot = PermissionManager.currentSnapshot()
        perfLog("PERMISSIONS: accessibility=\(snapshot.accessibility), inputMonitoring=\(snapshot.inputMonitoring), microphone=\(snapshot.microphone)")
    }

    func setupHotkey() {
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
}
