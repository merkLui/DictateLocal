import DictateCore
import SwiftUI

// MARK: - Prompt Editor

struct PromptEditor: View {
    @Binding var prompt: String
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Haiku Prompt")
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 560, height: 360)
            HStack {
                Button("Reset to Default") { text = ClaudeCleanup.defaultPrompt }
                    .disabled(text == ClaudeCleanup.defaultPrompt)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Storing nothing for the default lets later app versions improve it.
                    prompt = trimmed == ClaudeCleanup.defaultPrompt ? "" : trimmed
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .onAppear { text = prompt.isEmpty ? ClaudeCleanup.defaultPrompt : prompt }
    }
}
