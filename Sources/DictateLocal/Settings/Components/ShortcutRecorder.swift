import AppKit
import DictateCore
import SwiftUI

// MARK: - Shortcut Recorder

struct ShortcutRecorder: View {
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


struct KeyCaps: View {
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
