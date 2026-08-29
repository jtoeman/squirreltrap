import SwiftUI

/// Two-step NPS prompt: pick a 0-10 score, then an optional one-line reason.
/// Both steps are skippable -- picking a score already counts as a complete
/// response; the follow-up is a bonus, never required. Closing before
/// picking a score at all (the "x", clicking outside, Escape) is a dismissal
/// with no score recorded -- see PromptPanelView's popover binding.
///
/// Shown at most once per long cooldown (see
/// AppPreferences.lastNPSPromptShownAt / PromptPanelViewModel's eligibility
/// check) -- this view itself has no opinion on when it should appear, only
/// on how the two-step interaction looks once it does.
struct NPSPromptView: View {
    let themeAccent: Color
    var onSubmit: (_ score: Int, _ feedback: String?) -> Void

    @State private var selectedScore: Int?
    @State private var feedbackText = ""
    @FocusState private var isFeedbackFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedScore {
                Text("Thanks! What's the main reason for your score?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 240, alignment: .leading)

                TextField("Optional -- one line is plenty", text: $feedbackText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color.panelTextPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: 240)
                    .focused($isFeedbackFocused)
                    .onAppear { isFeedbackFocused = true }
                    .onSubmit { onSubmit(selectedScore, feedbackText.isEmpty ? nil : feedbackText) }

                HStack {
                    Button("Skip") { onSubmit(selectedScore, nil) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.panelTextSecondary)
                        .font(.system(size: 12))

                    Spacer()

                    Button("Submit") { onSubmit(selectedScore, feedbackText.isEmpty ? nil : feedbackText) }
                        .buttonStyle(.plain)
                        .foregroundStyle(themeAccent)
                        .font(.system(size: 12, weight: .semibold))
                }
            } else {
                Text("How likely are you to recommend Squirrel Trap to a friend or colleague?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 240, alignment: .leading)

                scoreGrid

                HStack {
                    Text("Not likely")
                    Spacer()
                    Text("Very likely")
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.panelTextSecondary)
                .frame(width: 240)
            }
        }
        .padding(14)
    }

    private var scoreGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0...5, id: \.self, content: scoreButton)
            }
            HStack(spacing: 5) {
                ForEach(6...10, id: \.self, content: scoreButton)
            }
        }
        .frame(width: 240)
    }

    private func scoreButton(_ score: Int) -> some View {
        Button {
            selectedScore = score
        } label: {
            Text("\(score)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(themeAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(themeAccent.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}
