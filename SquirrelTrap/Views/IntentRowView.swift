import SwiftUI

struct IntentRowView: View {
    let entry: IntentEntry
    var isHighlighted: Bool = false
    let onToggleCompleted: () -> Void
    let onToggleFavorite: () -> Void
    var onSetReminder: ((TimeInterval) -> Void)?
    var onCancelReminder: (() -> Void)?
    var onDelete: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingReminderPicker = false

    private static let reminderDurations: [(label: String, seconds: TimeInterval)] = [
        ("1 min", 1 * 60),
        ("2 min", 2 * 60),
        ("5 min", 5 * 60),
        ("10 min", 10 * 60),
        ("15 min", 15 * 60),
        ("30 min", 30 * 60),
        ("60 min", 60 * 60)
    ]

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleCompleted) {
                Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(entry.completed ? Color.accentColor : Color.accentColor.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.completed ? "Mark not done" : "Mark done")
            .accessibilityValue(entry.completed ? "Completed" : "Not completed")

            Text(entry.text)
                .font(.system(size: 13))
                .strikethrough(entry.completed)
                .foregroundStyle(Color.panelTextPrimary)
                .opacity(entry.completed ? 0.5 : 1.0)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            // Reminders only make sense for tasks you haven't finished yet.
            if !entry.completed, let onSetReminder, let onCancelReminder {
                reminderControl(onSetReminder: onSetReminder, onCancelReminder: onCancelReminder)
            }

            Button(action: onToggleFavorite) {
                Image(systemName: entry.favorite ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundStyle(entry.favorite ? Color("SunnyYellow") : Color.accentColor.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(entry.favorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(entry.favorite ? "Remove from favorites" : "Add to favorites")

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Delete")
                .accessibilityLabel("Delete")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isHighlighted ? 2 : 0)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isHighlighted)
    }

    @ViewBuilder
    private func reminderControl(onSetReminder: @escaping (TimeInterval) -> Void, onCancelReminder: @escaping () -> Void) -> some View {
        // Both states are the same plain Button — a Menu (used here previously
        // for the "pick a duration" state) has different internal chrome than
        // a Button even inside an identical outer frame, which kept shifting
        // this icon a couple points off the row's vertical center relative to
        // the star/checkbox next to it. Using a popover instead of Menu keeps
        // both states pixel-identical.
        Button {
            if entry.reminderDate != nil {
                onCancelReminder()
            } else {
                isShowingReminderPicker = true
            }
        } label: {
            Image(systemName: entry.reminderDate != nil ? "alarm.fill" : "alarm")
                .font(.system(size: 13))
                .foregroundStyle(entry.reminderDate != nil ? Color.accentColor : Color.accentColor.opacity(0.5))
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .help(entry.reminderDate != nil ? "Cancel reminder" : "Remind me later")
        .accessibilityLabel(entry.reminderDate != nil ? "Cancel reminder" : "Remind me later")
        .popover(isPresented: $isShowingReminderPicker) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.reminderDurations, id: \.seconds) { duration in
                    Button(duration.label) {
                        onSetReminder(duration.seconds)
                        isShowingReminderPicker = false
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
