import SwiftUI
import AppKit

struct LastDictationMenuItemView: View {
    let text: String
    let onCopy: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(width: 20, alignment: .center)
                
                Text("Copy dictation")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(text)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 80, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.1) : Color.clear)
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
