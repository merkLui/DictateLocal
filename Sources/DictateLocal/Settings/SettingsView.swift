import AppKit
import AVFoundation
import DictateCore
import ServiceManagement
import SwiftUI

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
    @AppStorage(replacementsKey) var replacements: String = TextCleanup.defaultReplacementsText
    @State var replacementRows: [ReplacementRow] = []
    @AppStorage(HotkeyPreferences.modeKey) var hotkeyMode: String = HotkeyPreferences.mode.rawValue
    @AppStorage(MicrophoneSelection.key) var microphoneUID: String = ""
    @State var microphones = MicrophoneSelection.devices
    @State var shortcut = HotkeyPreferences.shortcut
    @AppStorage("privacy_logging") var privacyLogging: Bool = true
    @AppStorage(cleanupEnabledKey) var cleanupEnabled = false
    @AppStorage(listFormattingEnabledKey) var listFormattingEnabled = false
    @AppStorage(claudeCleanupEnabledKey) var claudeCleanupEnabled = false
    @AppStorage(claudeReasoningKey) var claudeReasoning = ClaudeCleanup.Reasoning.low.rawValue
    @State var claudeKey = ""
    @State var hasClaudeKey = AnthropicKey.load() != nil
    @State var claudeConnection: ClaudeCleanup.Connection?
    @State var isEditingPrompt = false
    @AppStorage(claudePromptKey) var claudePrompt = ""
    @State var isCheckingClaude = false

    @ObservedObject var modelStatus = ModelStatus.shared
    @State var selectedSection: SettingsSection?
    @State var loginItemEnabled = SMAppService.mainApp.status == .enabled
    @State var logExportMessage: String = ""
    @State var permissions = PermissionManager.currentSnapshot()

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
    func fitWindowToPage() {
        let height: CGFloat
        switch selectedSection ?? .general {
        case .general:     height = 412
        case .model:       height = claudeCleanupEnabled ? 596 : 500
        case .vocabulary:  height = min(520, 118 + CGFloat(max(replacementRows.count, 1)) * 37)
        case .diagnostics: height = 382
        }
        (NSApp.windows.first { $0 is SettingsWindow } as? SettingsWindow)?.fitHeight(height)
    }


    func refreshPermissions() {
        permissions = PermissionManager.currentSnapshot()
    }
}

// MARK: - Window Background

/// Standard material for the content layer: the desktop shows through softly and text stays legible.
struct BehindWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}


// MARK: - Sidebar Icon

struct SettingsIconTile: View {
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


func clearInitialTextFocus() {
    for delay in [0.0, 0.05, 0.15, 0.4] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}
