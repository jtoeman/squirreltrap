import SwiftUI

/// Two-step NPS prompt: pick a 0-10 score, then an optional one-line reason.
/// Both steps are skippable -- picking a score already counts as a complete
/// response; the follow-up is a bonus, never required.
///
/// Three ways to leave step 1 without a score, each a different signal:
/// - "Not right now" -- an explicit, softer "ask me again soon" (see
///   PromptPanelViewModel.postponeNPSPrompt, a short 48h cooldown)
/// - the "x" / clicking outside / Escape -- a harder, more ambient signal
///   (PromptPanelViewModel.dismissNPSPrompt, the full long cooldown) -- see
///   PromptPanelView's popover binding for that path
///
/// Shown at most once per cooldown (see AppPreferences.lastNPSPromptShownAt
/// / PromptPanelViewModel's eligibility check) -- this view itself has no
/// opinion on when it should appear, only on how the interaction looks once
/// it does.
struct NPSPromptView: View {
    let themeAccent: Color
    var onSubmit: (_ score: Int, _ feedback: String?) -> Void
    var onNotRightNow: () -> Void

    @State private var selectedScore: Int?
    @State private var feedbackText = ""
    @FocusState private var isFeedbackFocused: Bool

    private let contentWidth: CGFloat = 290

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedScore {
                Text("Thanks! What's the main reason for your score?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: contentWidth, alignment: .leading)

                TextField("Optional -- one line is plenty", text: $feedbackText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color.panelTextPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: contentWidth)
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
                .frame(width: contentWidth)
            } else {
                Text("How likely are you to recommend Squirrel Trap to a friend or colleague?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: contentWidth, alignment: .leading)

                scoreRow

                HStack {
                    Text("Not likely")
                    Spacer()
                    Text("Very likely")
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.panelTextSecondary)
                .frame(width: contentWidth)

                Button("Not right now") { onNotRightNow() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.panelTextSecondary)
                    .font(.system(size: 12))
                    .frame(width: contentWidth, alignment: .center)
            }
        }
        .padding(14)
    }

    private var scoreRow: some View {
        HStack(spacing: 4) {
            ForEach(0...10, id: \.self, content: scoreButton)
        }
        .frame(width: contentWidth)
    }

    private func scoreButton(_ score: Int) -> some View {
        Button {
            selectedScore = score
        } label: {
            Text("\(score)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(themeAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(themeAccent.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}
