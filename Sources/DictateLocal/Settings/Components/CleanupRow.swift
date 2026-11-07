import AppKit
import SwiftUI

// MARK: - Cleanup Row

struct CleanupRow: View {
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
