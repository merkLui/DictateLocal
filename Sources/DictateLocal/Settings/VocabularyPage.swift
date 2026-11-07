import DictateCore
import SwiftUI

extension SettingsView {
    var vocabularyPage: some View {
        Form {
            Section {
                ForEach($replacementRows) { $row in
                    HStack(spacing: 10) {
                        TextField("Misheard", text: $row.from)
                            .labelsHidden()
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        TextField("Correct", text: $row.to)
                            .labelsHidden()
                        Button {
                            replacementRows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    .textFieldStyle(.plain)
                }
            } header: {
                HStack {
                    HStack(spacing: 4) {
                        Text("Replacements")
                        InfoButton(info: SettingInfo(
                            "Fixes words the speech model keeps getting wrong, after every dictation.",
                            ("Matches", "Whole words, in any capitalization"),
                            ("Example", "Cloud Code → Claude Code")))
                    }
                    Spacer()
                    Button("Add") {
                        replacementRows.append(ReplacementRow(from: "", to: ""))
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    Button("Restore Defaults") {
                        replacements = TextCleanup.defaultReplacementsText
                        loadReplacementRows()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: replacementRows) { _, rows in
            replacements = rows
                .filter { !$0.from.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { "\($0.from) -> \($0.to)" }
                .joined(separator: "\n")
        }
    }

    func loadReplacementRows() {
        replacementRows = TextCleanup.parseReplacements(replacements).map {
            ReplacementRow(from: $0.from, to: $0.to)
        }
    }
}

// MARK: - Replacement Row

struct ReplacementRow: Identifiable, Equatable {
    let id = UUID()
    var from: String
    var to: String
}
