import AppKit
import DictateCore
import ServiceManagement
import SwiftUI

extension SettingsView {
    var generalPage: some View {
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

    var launchesAtLogin: Binding<Bool> {
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

    var statusState: StatusHeader.State {
        switch modelStatus.state {
        case .downloading(let percent): return .downloading(percent: percent)
        case .preparing:                return .notReady("Preparing the speech model")
        case .failed:                   return .notReady("Speech model download failed")
        case .ready:
            return missingPermissionCount > 0 ? .notReady("Needs access, see Diagnostics") : .ready
        }
    }

    var missingPermissionCount: Int {
        [permissions.accessibility, permissions.inputMonitoring, permissions.microphone].filter { !$0 }.count
    }
}
