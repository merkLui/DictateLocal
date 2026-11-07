import SwiftUI

// MARK: - Rows

struct PermissionRow: View {
    let title: String
    let purpose: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent {
            if isGranted {
                Text("Granted")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Text("Not granted")
                        .foregroundStyle(.orange)
                    Button("Grant Access…", action: action)
                }
            }
        } label: {
            Label {
                TitleWithInfo(title: title, info: SettingInfo(purpose))
            } icon: {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(isGranted ? .green : .orange)
            }
        }
    }
}
