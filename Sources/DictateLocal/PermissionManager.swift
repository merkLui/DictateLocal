import Cocoa
import ApplicationServices
import AVFoundation

struct PermissionSnapshot {
    let accessibility: Bool
    let inputMonitoring: Bool
    let microphone: Bool
    
    var allGranted: Bool {
        accessibility && inputMonitoring && microphone
    }
}

enum PermissionManager {
    static func currentSnapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        )
    }
    
    static func requestMissingPermissions() {
        requestAccessibilityPermission()
        requestInputMonitoringPermission()
        requestMicrophonePermission()
    }
    
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    static func requestInputMonitoringPermission() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }
    
    static func openAccessibilitySettings() {
        openSettings(anchor: "Privacy_Accessibility")
    }
    
    static func openInputMonitoringSettings() {
        openSettings(anchor: "Privacy_ListenEvent")
    }
    
    static func openMicrophoneSettings() {
        openSettings(anchor: "Privacy_Microphone")
    }
    
    static func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        } else if status == .denied || status == .restricted {
            openMicrophoneSettings()
        }
    }
    
    private static func openSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
