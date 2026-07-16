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
    var onDragHandleHoverChanged: (Bool) -> Void = { _ in }

    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(Color.panelTextSecondary.opacity(0.5))
                // The panel is otherwise movable by clicking/dragging its
                // background (isMovableByWindowBackground) -- a plain Image
                // isn't an AppKit "control", so without this a click-drag on
                // the handle was being claimed by that window-move behavior
                // instead of starting the item drag below. Disabling it while
                // hovering the handle (before mouseDown) lets .draggable win.
                .onHover { hovering in onDragHandleHoverChanged(hovering) }
                .draggable(entry.id.uuidString) {
                    // Explicit width matters: without it, a preview dragged from
                    // this small handle rendered as just the system drag-operation
                    // badge with no visible content at all.
                    HStack(spacing: 10) {
                        Image(systemName: "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.accentColor.opacity(0.5))
                        Text(entry.text)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelTextPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(width: 380, alignment: .leading)
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
