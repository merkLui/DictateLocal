import AppKit
import DictateCore
import SwiftUI

// MARK: - Speech Model Row

struct SpeechModelRow: View {
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
