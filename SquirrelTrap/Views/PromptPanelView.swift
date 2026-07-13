import SwiftUI

struct PromptPanelView: View {
    @ObservedObject var viewModel: PromptPanelViewModel
    @ObservedObject var intentStore: IntentStore
    @FocusState private var isInputFocused: Bool
    var onDismiss: () -> Void
    var onEscape: () -> Void
    var onOpenPreferences: () -> Void

    init(viewModel: PromptPanelViewModel, onDismiss: @escaping () -> Void, onEscape: @escaping () -> Void, onOpenPreferences: @escaping () -> Void) {
        self.viewModel = viewModel
        self.intentStore = viewModel.intentStore
        self.onDismiss = onDismiss
        self.onEscape = onEscape
        self.onOpenPreferences = onOpenPreferences
    }

    // Pending items always float above completed ones, each group newest-first.
    private var pendingEntries: [IntentEntry] {
        intentStore.visibleEntries.filter { !$0.completed }
    }

    private var completedEntries: [IntentEntry] {
        intentStore.visibleEntries.filter { $0.completed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            actionRow

            if viewModel.isShowingFavorites {
                favoritesList
            } else {
                entriesList
            }

            footer
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 10)
        .frame(width: 420, height: 340, alignment: .top)
        // SwiftUI's own exit-command path — needed alongside DismissiblePanel's
        // AppKit-level cancelOperation because a focused TextField sometimes
        // swallows Escape before it ever reaches the responder chain. Both
        // paths funnel into the same guarded handler (see PanelController),
        // so whichever one actually fires, confirmation dialogs are still
        // respected and double-firing is harmless.
        .onExitCommand(perform: onEscape)
        .onAppear { if !viewModel.isShowingFavorites { isInputFocused = true } }
        .onChange(of: viewModel.focusToken) { _, _ in
            if !viewModel.isShowingFavorites { isInputFocused = true }
        }
    }

    private var header: some View {
        Text("Squirrel Trap")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.panelTextSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var footer: some View {
        HStack {
            Button(action: onOpenPreferences) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Preferences")
            .accessibilityLabel("Preferences")

            Spacer()

            KofiButton(onOpened: onDismiss)
        }
    }

    /// Text entry (or, in favorites mode, a label) plus the favorites toggle —
    /// always in the same row so the toggle stays reachable in either mode.
    private var actionRow: some View {
        HStack(spacing: 8) {
            if viewModel.isShowingFavorites {
                Text("Favorites")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.panelTextPrimary)
                Spacer(minLength: 0)
            } else {
                TextField("What are you about to do?", text: $viewModel.draftText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.panelTextPrimary)
                    .padding(10)
                    .glassCard()
                    .focused($isInputFocused)
                    .onSubmit { viewModel.submit(dismiss: onDismiss) }
            }

            Button {
                viewModel.isShowingFavorites.toggle()
            } label: {
                Image(systemName: viewModel.isShowingFavorites ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundStyle(viewModel.isShowingFavorites ? Color("SunnyYellow") : Color.accentColor.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Favorites")
            .accessibilityLabel(viewModel.isShowingFavorites ? "Back to your list" : "Show favorites")
        }
    }

    private var entriesList: some View {
        Group {
            if pendingEntries.isEmpty && completedEntries.isEmpty {
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(pendingEntries) { entry in
                            IntentRowView(
                                entry: entry,
                                isHighlighted: entry.id == viewModel.highlightedEntryID,
                                onToggleCompleted: { intentStore.toggleCompleted(id: entry.id) },
                                onToggleFavorite: { intentStore.toggleFavorite(id: entry.id) },
                                onSetReminder: { duration in viewModel.setReminder(for: entry.id, duration: duration) },
                                onCancelReminder: { viewModel.cancelReminder(for: entry.id) }
                            )
                        }

                        if !completedEntries.isEmpty {
                            Text("Completed")
                                .font(.caption)
                                .foregroundStyle(Color.panelTextSecondary)
                                .padding(.top, pendingEntries.isEmpty ? 0 : 4)

                            ForEach(completedEntries) { entry in
                                IntentRowView(
                                    entry: entry,
                                    onToggleCompleted: { intentStore.toggleCompleted(id: entry.id) },
                                    onToggleFavorite: { intentStore.toggleFavorite(id: entry.id) },
                                    onDelete: { intentStore.delete(id: entry.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var favoritesList: some View {
        Group {
            if intentStore.favoriteEntries.isEmpty {
                Text("No favorites yet — tap the star on any item to save it here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.panelTextSecondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(intentStore.favoriteEntries) { entry in
                            HStack(spacing: 10) {
                                Button {
                                    viewModel.repeatFavorite(entry)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.clockwise.circle.fill")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.accentColor)
                                        Text(entry.text)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.panelTextPrimary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Log this again")
                                .accessibilityLabel("Log \(entry.text) again")

                                Button {
                                    intentStore.toggleFavorite(id: entry.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from favorites")
                                .accessibilityLabel("Remove from favorites")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .glassCard()
                        }
                    }
                }
            }
        }
    }
}
