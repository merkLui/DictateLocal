import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var diagnosticsPage: some View {
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

    func exportLogs() {
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

    func clearLogs() {
        AppLogger.clearLog()
        logExportMessage = "Log cleared."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { logExportMessage = "" }
    }
}
