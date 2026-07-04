import SwiftUI

struct IntentRowView: View {
    let entry: IntentEntry
    let onToggleCompleted: () -> Void
    let onToggleFavorite: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleCompleted) {
                Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(entry.completed ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(entry.text)
                .font(.system(size: 13))
                .strikethrough(entry.completed)
                .foregroundStyle(entry.completed ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            Button(action: onToggleFavorite) {
                Image(systemName: entry.favorite ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundStyle(entry.favorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(entry.favorite ? "Remove from favorites" : "Add to favorites")

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
