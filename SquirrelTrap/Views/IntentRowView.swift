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
        // Button and Menu have different intrinsic sizing by default — without
        // pinning both to the same fixed frame, swapping between them (active vs.
        // inactive reminder state) visibly shifted this icon off the row's
        // vertical center relative to the star/checkbox next to it.
        Group {
            if entry.reminderDate != nil {
                Button(action: onCancelReminder) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Cancel reminder")
                .accessibilityLabel("Cancel reminder")
            } else {
                Menu {
                    ForEach(Self.reminderDurations, id: \.seconds) { duration in
                        Button(duration.label) { onSetReminder(duration.seconds) }
                    }
                } label: {
                    Image(systemName: "alarm")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Remind me later")
                .accessibilityLabel("Remind me later")
            }
        }
        .frame(width: 20, height: 20)
    }
}
