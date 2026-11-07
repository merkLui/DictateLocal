import DictateCore
import SwiftUI

// MARK: - Info Button

/// What an info button explains: one sentence, then short facts.
struct SettingInfo {
    let summary: String
    let facts: [(label: String, value: String)]

    init(_ summary: String, _ facts: (label: String, value: String)...) {
        self.summary = summary
        self.facts = facts
    }
}

extension SpeechModel {
    var info: SettingInfo {
        switch self {
        case .nemotron:
            return SettingInfo("Streaming: types at the cursor while you speak.",
                               ("Delay", "About 2 s behind your voice"),
                               ("Disk", "590 MB"),
                               ("Memory", "About 110 MB"))
        case .parakeetUltra:
            return SettingInfo("Inserts the whole text once when you stop.",
                               ("Wait", "Under 1 s after you stop"),
                               ("Disk", "About 600 MB"),
                               ("Memory", "About 150 MB"))
        }
    }
}

/// A row title with an info button right after it.
struct TitleWithInfo: View {
    let title: String
    let info: SettingInfo

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            InfoButton(info: info)
        }
    }
}

struct InfoButton: View {
    let info: SettingInfo
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Info")
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(info.summary)
                    .fixedSize(horizontal: false, vertical: true)
                if !info.facts.isEmpty {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
                        ForEach(info.facts.indices, id: \.self) { index in
                            GridRow {
                                Text(info.facts[index].label)
                                    .foregroundStyle(.secondary)
                                Text(info.facts[index].value)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.callout)
                }
            }
            .frame(width: 300, alignment: .leading)
            .padding(14)
        }
    }
}
