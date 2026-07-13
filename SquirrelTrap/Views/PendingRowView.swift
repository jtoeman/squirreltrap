import SwiftUI

/// Wraps IntentRowView with a drag handle for reordering, without touching
/// IntentRowView itself — only the handle carries `.draggable`, so the
/// checkbox/star/reminder/delete buttons inside IntentRowView keep working
/// with no gesture conflicts.
struct PendingRowView: View {
    let entry: IntentEntry
    var isHighlighted: Bool = false
    let onToggleCompleted: () -> Void
    let onToggleFavorite: () -> Void
    let onSetReminder: (TimeInterval) -> Void
    let onCancelReminder: () -> Void
    let onDrop: (UUID) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(Color.panelTextSecondary.opacity(0.5))
                .draggable(entry.id.uuidString) {
                    Text(entry.text)
                        .font(.system(size: 13))
                        .padding(8)
                        .glassCard()
                }

            IntentRowView(
                entry: entry,
                isHighlighted: isHighlighted || isDropTargeted,
                onToggleCompleted: onToggleCompleted,
                onToggleFavorite: onToggleFavorite,
                onSetReminder: onSetReminder,
                onCancelReminder: onCancelReminder
            )
        }
        .dropDestination(for: String.self) { items, _ in
            guard let draggedIDString = items.first, let draggedID = UUID(uuidString: draggedIDString) else { return false }
            onDrop(draggedID)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }
}
