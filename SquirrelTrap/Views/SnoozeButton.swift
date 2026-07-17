import SwiftUI

/// Matches KofiButton's native-button styling (same shape/padding/font) with
/// a green background instead of the Ko-fi blue.
struct SnoozeButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                Text("Snooze")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Color("ForestGreen"),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }
}
