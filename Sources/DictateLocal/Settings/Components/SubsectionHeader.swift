import SwiftUI

// MARK: - Subsection Header

/// A smaller header for a group within a section, aligned with the edge of its box.
struct SubsectionHeader: View {
    let title: String

    /// How far the groups under a section move in.
    static let indent: CGFloat = 20

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            // Headers sit 10 pt inside their box; this one starts at the box edge.
            .padding(.leading, -10)
    }
}

extension View {
    /// One group of a page built from several forms.
    func subform(indented: Bool = false) -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, indented ? SubsectionHeader.indent : 0)
    }
}
