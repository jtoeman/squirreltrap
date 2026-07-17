import SwiftUI

struct PromptPanelView: View {
    @ObservedObject var viewModel: PromptPanelViewModel
    @ObservedObject var intentStore: IntentStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var reminderSyncEngine: ReminderSyncEngine
    @FocusState private var isInputFocused: Bool
    @State private var isEndDropTargeted = false
    var onDismiss: () -> Void
    var onEscape: () -> Void
    var onOpenPreferences: () -> Void
    var onDragHandleHoverChanged: (Bool) -> Void

    init(
        viewModel: PromptPanelViewModel,
        preferences: AppPreferences,
        reminderSyncEngine: ReminderSyncEngine,
        onDismiss: @escaping () -> Void,
        onEscape: @escaping () -> Void,
        onOpenPreferences: @escaping () -> Void,
        onDragHandleHoverChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.intentStore = viewModel.intentStore
        self.preferences = preferences
        self.reminderSyncEngine = reminderSyncEngine
        self.onDismiss = onDismiss
        self.onEscape = onEscape
        self.onOpenPreferences = onOpenPreferences
        self.onDragHandleHoverChanged = onDragHandleHoverChanged
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

            if reminderSyncEngine.isSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing Reminders…")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.panelTextSecondary)
                }
            }

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
        HStack(spacing: 8) {
            Button(action: onOpenPreferences) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Preferences")
            .accessibilityLabel("Preferences")

            snoozeControl

            Spacer()

            KofiButton(onOpened: onDismiss)
        }
    }

    /// Rapidly switching apps can turn the popup itself into the annoyance —
    /// Snooze suppresses Cmd+Tab triggering it for a bit (the menu bar icon
    /// and Cmd+, still work, and clicking the icon cancels the snooze early).
    /// Duration is configured in Preferences, not here.
    private var snoozeControl: some View {
        Button("Snooze") {
            preferences.snoozeUntil = Date().addingTimeInterval(preferences.snoozeDurationMinutes * 60)
            onDismiss()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(Color.accentColor)
        .help("Snooze Cmd+Tab for a while")
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
                            PendingRowView(
                                entry: entry,
                                isHighlighted: entry.id == viewModel.highlightedEntryID,
                                onToggleCompleted: { intentStore.toggleCompleted(id: entry.id) },
                                onToggleFavorite: { intentStore.toggleFavorite(id: entry.id) },
                                onSetReminder: { duration in viewModel.setReminder(for: entry.id, duration: duration) },
                                onCancelReminder: { viewModel.cancelReminder(for: entry.id) },
                                onDrop: { draggedID in intentStore.movePendingEntry(id: draggedID, before: entry.id) },
                                onDragHandleHoverChanged: onDragHandleHoverChanged
                            )
                        }

                        // Every row above only offers "drop before me" — without
                        // this, there's no way to drag something to the very
                        // bottom of the pending list.
                        if !pendingEntries.isEmpty {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isEndDropTargeted ? Color.accentColor.opacity(0.24) : Color.clear)
                                .frame(height: 14)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let draggedIDString = items.first, let draggedID = UUID(uuidString: draggedIDString) else { return false }
                                    intentStore.movePendingEntryToEnd(id: draggedID)
                                    return true
                                } isTargeted: { targeted in
                                    isEndDropTargeted = targeted
                                }
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
