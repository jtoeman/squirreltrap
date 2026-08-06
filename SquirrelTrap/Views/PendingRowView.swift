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
    let onSetColor: (TodoColorTag?) -> Void
    let onDrop: (UUID) -> Void
    var onDragHandleHoverChanged: (Bool) -> Void = { _ in }

    @State private var isDropTargeted = false
    // Completion-animation state -- see startCompletionAnimation(). Purely
    // visual, not persisted.
    @State private var rowScale: CGFloat = 1.0
    @State private var rowOpacity: Double = 1.0
    @State private var showPuff = false
    @State private var puffOpacity: Double = 0.0

    var body: some View {
        HStack(spacing: 6) {
            IntentRowView(
                entry: entry,
                isHighlighted: isHighlighted || isDropTargeted,
                onToggleCompleted: startCompletionAnimation,
                onToggleFavorite: onToggleFavorite,
                onSetReminder: onSetReminder,
                onCancelReminder: onCancelReminder,
                onSetColor: onSetColor
            )

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
        }
        .scaleEffect(rowScale)
        .opacity(rowOpacity)
        .overlay {
            if showPuff {
                Text("💨")
                    .font(.system(size: 16))
                    .opacity(puffOpacity)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let draggedIDString = items.first, let draggedID = UUID(uuidString: draggedIDString) else { return false }
            onDrop(draggedID)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    /// Plays the shrink/fade-out + puff-cloud animation in place, then calls
    /// the real onToggleCompleted() only once the row is fully invisible --
    /// this entry then moves from the pending list to the completed one, but
    /// since there's nothing left on screen to jump, that structural move is
    /// never actually visible. Timed as a fraction of celebrationDuration
    /// (Core/CelebrationTiming.swift), the same knob the main panel's icon
    /// pulse uses, so both halves of the celebration stay in the same
    /// ballpark even though this row's animation runs first and completes
    /// before that pulse begins.
    private func startCompletionAnimation() {
        let outDuration = celebrationDuration * 0.6
        let puffDuration = celebrationDuration * 0.4

        withAnimation(.easeIn(duration: outDuration)) {
            rowScale = 0.01
            rowOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + outDuration) {
            showPuff = true
            withAnimation(.easeOut(duration: puffDuration * 0.4)) {
                puffOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + puffDuration * 0.4) {
                withAnimation(.easeIn(duration: puffDuration * 0.6)) {
                    puffOpacity = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + puffDuration) {
                onToggleCompleted()
            }
        }
    }
}
