import Foundation

@MainActor
final class PromptPanelViewModel: ObservableObject {
    @Published var draftText: String = ""
    @Published var focusToken = UUID()
    @Published var isShowingFavorites = false

    let intentStore: IntentStore

    init(intentStore: IntentStore) {
        self.intentStore = intentStore
    }

    /// Called every time the panel is about to be shown: clears the draft, bumps
    /// focusToken so the text field reliably re-focuses even if the panel view's
    /// identity didn't change, and drops back out of favorites mode from any
    /// previous show.
    func reset() {
        draftText = ""
        focusToken = UUID()
        isShowingFavorites = false
    }

    func submit(dismiss: () -> Void) {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            intentStore.add(text: trimmed)
        }
        dismiss()
    }

    /// Logs a fresh copy of a favorited intent, then drops back to the normal
    /// list so the user immediately sees it land at the top.
    func repeatFavorite(_ entry: IntentEntry) {
        intentStore.add(text: entry.text)
        isShowingFavorites = false
    }
}
