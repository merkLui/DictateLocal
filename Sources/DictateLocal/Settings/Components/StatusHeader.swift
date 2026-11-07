import AppKit
import SwiftUI

// MARK: - Status Header

struct StatusHeader: View {
    enum State: Equatable {
        case ready
        case downloading(percent: Int)
        case notReady(String)
    }

    let state: State

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "DictateLocal"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(appName)
                    .font(.title3.weight(.semibold))
                status
                    .font(.callout)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .ready:
            statusLine(color: .green, text: "Ready")
        case .notReady(let text):
            statusLine(color: .orange, text: text)
        case .downloading(let percent):
            HStack(spacing: 8) {
                ProgressView(value: Double(percent), total: 100)
                    .frame(width: 120)
                Text("Downloading speech model, \(percent) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusLine(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
