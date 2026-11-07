import SwiftUI

// MARK: - Install Progress

/// Spins until there is a real percentage, and again for the work after the download.
struct InstallProgress: View {
    let percent: Int

    static func status(percent: Int, finishing: String) -> String {
        switch percent {
        case 0:   return "Starting download…"
        case 100: return finishing
        default:  return "Downloading, \(percent) %"
        }
    }

    var body: some View {
        Group {
            if percent == 0 || percent == 100 {
                ProgressView()
            } else {
                ProgressView(value: Double(percent), total: 100)
                    .progressViewStyle(.circular)
            }
        }
        .controlSize(.small)
        .frame(width: 28, height: 28)
    }
}
