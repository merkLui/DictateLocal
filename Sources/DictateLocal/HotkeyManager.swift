import Cocoa
import DictateCore

enum HotkeyState {
    case pressed
    case released
    case canceled
}

enum HotkeyPreferences {
    private static let shortcutKey = "hotkey_shortcut"
    static let modeKey = "hotkey_mode"
    static let didChange = Notification.Name("HotkeyPreferencesDidChange")

    static var shortcut: HotkeyShortcut {
        get {
            if let data = UserDefaults.standard.data(forKey: shortcutKey),
               let stored = try? JSONDecoder().decode(HotkeyShortcut.self, from: data) {
                return stored
            }
            // Settings from the first version of the app.
            switch UserDefaults.standard.string(forKey: "activation_key") {
            case "rightOption":  return HotkeyShortcut(keys: [.init(code: 61, label: "right ⌥")])
            case "rightCommand": return HotkeyShortcut(keys: [.init(code: 54, label: "right ⌘")])
            default:             return .default
            }
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: shortcutKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static var mode: HotkeyMode {
        if let raw = UserDefaults.standard.string(forKey: modeKey), let mode = HotkeyMode(rawValue: raw) {
            return mode
        }
        return UserDefaults.standard.string(forKey: "fn_key_behavior") == "hold_only" ? .hold : .holdOrPress
    }
}

class HotkeyManager {
    enum RecordingResult {
        case recorded(HotkeyShortcut)
        case invalid(HotkeyShortcut.ValidationError)
        case canceled
    }

    /// Presses shorter than this count as a tap.
    private let tapThreshold: TimeInterval = 0.30
    private let escapeCode: UInt16 = 53

    private var matcher = HotkeyMatcher(shortcut: HotkeyPreferences.shortcut)
    private var pressStartTime: Date?
    /// Set when a press finished hands-free dictation, so its release is not treated as a new tap.
    private var swallowNextRelease = false
    private var swallowedKeyDowns = Set<UInt16>()

    private var runLoopSource: CFRunLoopSource?
    private var eventPort: CFMachPort?
    private var retryTimer: Timer?

    private var onRecordingFinished: ((RecordingResult) -> Void)?
    private var recordedKeys: [HotkeyShortcut.Key] = []
    private var recordingPressed = Set<UInt16>()
    private var recordingTimeout: Timer?

    // Callback to Delegate
    private let stateChanged: (HotkeyState) -> Void

    var canListen: Bool { eventPort != nil }

    init(stateChanged: @escaping (HotkeyState) -> Void) {
        self.stateChanged = stateChanged
        setupEventTap()
        NotificationCenter.default.addObserver(forName: HotkeyPreferences.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.matcher.shortcut = HotkeyPreferences.shortcut
        }
    }

    deinit {
        if let eventPort {
            CGEvent.tapEnable(tap: eventPort, enable: false)
        }
    }

    // MARK: - Shortcut Recording

    /// The next keys pressed become the result instead of triggering anything.
    func startRecording(completion: @escaping (RecordingResult) -> Void) {
        onRecordingFinished = completion
        recordedKeys = []
        recordingPressed = []
        matcher.reset()
        recordingTimeout?.invalidate()
        recordingTimeout = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.finishRecording(.canceled)
        }
    }

    func cancelRecording() {
        finishRecording(.canceled)
    }

    private func finishRecording(_ result: RecordingResult) {
        recordingTimeout?.invalidate()
        let completion = onRecordingFinished
        onRecordingFinished = nil
        matcher.reset()
        completion?(result)
    }

    private func handleRecordingEvent(code: UInt16, isDown: Bool, label: String?) {
        if isDown {
            if code == escapeCode, recordedKeys.isEmpty {
                finishRecording(.canceled)
                return
            }
            recordingPressed.insert(code)
            if !recordedKeys.contains(where: { $0.code == code }) {
                recordedKeys.append(.init(code: code, label: label ?? "Key \(code)"))
            }
            return
        }

        recordingPressed.remove(code)
        guard recordingPressed.isEmpty, !recordedKeys.isEmpty else { return }

        // Modifiers read first, as on a menu shortcut.
        let ordered = recordedKeys.filter { HotkeyShortcut.isModifier($0.code) }
            + recordedKeys.filter { !HotkeyShortcut.isModifier($0.code) }
        let shortcut = HotkeyShortcut(keys: ordered)
        if let error = shortcut.validate() {
            finishRecording(.invalid(error))
        } else {
            finishRecording(.recorded(shortcut))
        }
    }

    // MARK: - Event Tap

    private func setupEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEventTap(type: type, event: event)
            },
            userInfo: observer
        ) else {
            // Works without a restart once Input Monitoring is granted.
            perfLog("HOTKEY: Could not create event tap; retrying")
            if retryTimer == nil {
                retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    self?.setupEventTap()
                }
            }
            return
        }

        retryTimer?.invalidate()
        retryTimer = nil
        eventPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            perfLog("HOTKEY: Event tap disabled; re-enabling")
            if let eventPort {
                CGEvent.tapEnable(tap: eventPort, enable: true)
            }
            // Key releases may have been missed while the tap was off.
            matcher.reset()
            swallowedKeyDowns.removeAll()
            return Unmanaged.passRetained(event)
        }

        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isDown: Bool
        switch type {
        case .flagsChanged:
            guard let modifierIsDown = Self.modifierIsDown(code: code, flags: event.flags) else {
                return Unmanaged.passRetained(event)
            }
            isDown = modifierIsDown
        case .keyDown:
            isDown = true
        case .keyUp:
            isDown = false
        default:
            return Unmanaged.passRetained(event)
        }

        if onRecordingFinished != nil {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                handleRecordingEvent(code: code, isDown: isDown, label: Self.label(code: code, event: event))
            }
            return nil
        }

        if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return swallowedKeyDowns.contains(code) ? nil : Unmanaged.passRetained(event)
        }

        switch matcher.handle(code: code, isDown: isDown) {
        case .activated:
            handleActivated()
        case .deactivated:
            DispatchQueue.main.async { [weak self] in self?.handleDeactivated() }
        case .interrupted:
            handleInterrupted()
        case nil:
            break
        }

        return shouldSwallow(code: code, type: type, isDown: isDown) ? nil : Unmanaged.passRetained(event)
    }

    private func shouldSwallow(code: UInt16, type: CGEventType, isDown: Bool) -> Bool {
        // Fn must not open the emoji picker. Other modifiers keep working for the system.
        if type == .flagsChanged {
            return code == HotkeyShortcut.fnCode && matcher.shortcut.codes.contains(code)
        }
        if isDown {
            guard matcher.isActive, matcher.shortcut.codes.contains(code) else { return false }
            swallowedKeyDowns.insert(code)
            return true
        }
        return swallowedKeyDowns.remove(code) != nil
    }

    // MARK: - Gestures

    private func handleActivated() {
        // The tap callback runs on the main run loop, so the delegate state can be read directly.
        if let delegate = NSApp.delegate as? AppDelegate,
           delegate.isCapturingAudio,
           delegate.currentRecordMode == .toggle {
            swallowNextRelease = true
            DispatchQueue.main.async { [weak self] in
                self?.stateChanged(.released)
            }
            return
        }

        pressStartTime = Date()
        DispatchQueue.main.async { [weak self] in
            self?.stateChanged(.pressed)
        }
    }

    private func handleDeactivated() {
        if swallowNextRelease {
            swallowNextRelease = false
            return
        }

        // A press while the previous dictation is still being processed starts nothing.
        guard let delegate = NSApp.delegate as? AppDelegate, delegate.isCapturingAudio else { return }

        let isTap = (pressStartTime.map { Date().timeIntervalSince($0) } ?? 0) < tapThreshold
        switch HotkeyPreferences.mode {
        case .hold:
            stateChanged(isTap ? .canceled : .released)
        case .press:
            switchToHandsFree(delegate)
        case .holdOrPress:
            if isTap {
                switchToHandsFree(delegate)
            } else {
                stateChanged(.released)
            }
        }
    }

    private func switchToHandsFree(_ delegate: AppDelegate) {
        delegate.currentRecordMode = .toggle
        delegate.hudWindow?.showHUD(mode: .toggle)
    }

    /// Right ⌘ then C right away is a copy, not a dictation.
    private func handleInterrupted() {
        guard matcher.shortcut.isModifierOnly,
              let start = pressStartTime, Date().timeIntervalSince(start) < tapThreshold else { return }
        matcher.deactivate()
        DispatchQueue.main.async { [weak self] in
            self?.stateChanged(.canceled)
        }
    }

    // MARK: - Key Details

    /// Device-specific flags, which tell left and right modifier keys apart.
    private static func modifierIsDown(code: UInt16, flags: CGEventFlags) -> Bool? {
        let mask: UInt64
        switch code {
        case 59: mask = 0x0001
        case 56: mask = 0x0002
        case 60: mask = 0x0004
        case 55: mask = 0x0008
        case 54: mask = 0x0010
        case 58: mask = 0x0020
        case 61: mask = 0x0040
        case 62: mask = 0x2000
        case HotkeyShortcut.fnCode: mask = CGEventFlags.maskSecondaryFn.rawValue
        default: return nil
        }
        return flags.rawValue & mask != 0
    }

    private static let specialLabels: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 76: "Enter",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]

    private static func label(code: UInt16, event: CGEvent) -> String? {
        if let modifier = HotkeyShortcut.modifierLabel(for: code) { return modifier }
        if let special = specialLabels[code] { return special }
        return NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased()
    }
}
