import SwiftUI

struct PromptPanelView: View {
    @ObservedObject var viewModel: PromptPanelViewModel
    @ObservedObject var intentStore: IntentStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var reminderSyncEngine: ReminderSyncEngine
    @ObservedObject var updateChecker: UpdateChecker
    @FocusState private var isInputFocused: Bool
    @State private var isEndDropTargeted = false
    @State private var showingClearCompletedConfirm = false
    // Celebration-animation state, driven by runCelebrationAnimation() below
    // when viewModel.isCelebrating flips true -- see that function for
    // the timeline. Purely visual, not persisted. The row-shrink/puff-cloud
    // half of the celebration lives on the individual to-do row instead --
    // see PendingRowView.startCompletionAnimation.
    @State private var iconScale: CGFloat = 1.0
    @State private var countScale: CGFloat = 1.0
    // Which CoachTip (if any) is currently popped over its anchor button --
    // see checkForCoachTip(). Not persisted; only whether a tip has ever
    // fired is (implicitly, via AppPreferences.totalPanelShows only ever
    // equaling any given trigger count once).
    @State private var activeCoachTip: CoachTip?
    // Gates AnalyticsConsentPrompt to at most once per launch even if this
    // view re-appears multiple times before the user answers it.
    @State private var isShowingAnalyticsConsent = false
    @State private var isShowingNPSPrompt = false
    var onDismiss: () -> Void
    var onEscape: () -> Void
    var onOpenPreferences: () -> Void
    var onSnooze: () -> Void
    var onDragHandleHoverChanged: (Bool) -> Void

    init(
        viewModel: PromptPanelViewModel,
        preferences: AppPreferences,
        reminderSyncEngine: ReminderSyncEngine,
        updateChecker: UpdateChecker,
        onDismiss: @escaping () -> Void,
        onEscape: @escaping () -> Void,
        onOpenPreferences: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDragHandleHoverChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.intentStore = viewModel.intentStore
        self.preferences = preferences
        self.reminderSyncEngine = reminderSyncEngine
        self.updateChecker = updateChecker
        self.onDismiss = onDismiss
        self.onEscape = onEscape
        self.onOpenPreferences = onOpenPreferences
        self.onSnooze = onSnooze
        self.onDragHandleHoverChanged = onDragHandleHoverChanged
    }

    private var themeAccent: Color { preferences.panelTheme.accent }

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
            activitySummary

            if let update = updateChecker.availableUpdate {
                Link(destination: update.url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Update available: v\(update.version)")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(themeAccent)
            }

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
        .frame(width: 520, height: 460, alignment: .top)
        // SwiftUI's own exit-command path — needed alongside DismissiblePanel's
        // AppKit-level cancelOperation because a focused TextField sometimes
        // swallows Escape before it ever reaches the responder chain. Both
        // paths funnel into the same guarded handler (see PanelController),
        // so whichever one actually fires, confirmation dialogs are still
        // respected and double-firing is harmless.
        .onExitCommand(perform: onEscape)
        .onAppear {
            // Deferred a tick -- setting @FocusState synchronously inside
            // onAppear can fire mid-update-cycle on macOS, which is what
            // produces SwiftUI's "Publishing changes from within view
            // updates is not allowed" console warning. Async lets the
            // current update transaction finish first; the focus change
            // still lands effectively instantly.
            if !viewModel.isShowingFavorites {
                DispatchQueue.main.async { isInputFocused = true }
            }
            // A consent decision takes priority over the coach-tip rotation
            // on any appearance where it hasn't been answered yet -- both are
            // popovers anchored in this same view, and showing both at once
            // would just be visual noise for a choice that only needs asking
            // one time, ever.
            if !preferences.hasAskedAnalyticsConsent {
                isShowingAnalyticsConsent = true
            } else {
                checkForCoachTip()
            }
        }
        .onChange(of: viewModel.focusToken) { _, _ in
            if !viewModel.isShowingFavorites {
                DispatchQueue.main.async { isInputFocused = true }
            }
        }
        .onChange(of: preferences.totalPanelShows) { _, _ in
            guard preferences.hasAskedAnalyticsConsent else { return }
            checkForCoachTip()
        }
        .onChange(of: viewModel.pendingNPSPrompt) { _, isPending in
            guard isPending else { return }
            viewModel.pendingNPSPrompt = false
            // Don't stack it on top of a coach tip or the consent ask --
            // both are popovers anchored in this same header; NPS just
            // waits for its own next eligible completion rather than
            // fighting another popover for the same anchor point right now.
            guard activeCoachTip == nil, !isShowingAnalyticsConsent else { return }
            isShowingNPSPrompt = true
        }
    }

    private func decideAnalyticsConsent(enabled: Bool) {
        preferences.analyticsEnabled = enabled
        preferences.hasAskedAnalyticsConsent = true
        AnalyticsService.shared.updateConsent(enabled: enabled)
        isShowingAnalyticsConsent = false
    }

    /// Every 4th show starting at the 2nd (2, 6, 10, 14, ...) picks the next
    /// tip in the rotation through whatever hasn't been individually
    /// dismissed yet, via coachTipRotationIndex -- an undismissed tip keeps
    /// recurring as the cycle comes back around, so this doesn't stop until
    /// every tip has eventually been dismissed (or Reset All Tips runs).
    private func checkForCoachTip() {
        guard preferences.showTips else { return }
        let count = preferences.totalPanelShows
        guard count >= 2, (count - 2).isMultiple(of: 4) else { return }
        let undismissed = CoachTip.allCases.filter { !preferences.dismissedCoachTips.contains($0.rawValue) }
        guard !undismissed.isEmpty else { return }
        let tip = undismissed[preferences.coachTipRotationIndex % undismissed.count]
        activeCoachTip = tip
        preferences.coachTipRotationIndex += 1
        AnalyticsService.shared.track(.coachTipShown, properties: ["tip_id": tip.rawValue])
    }

    /// Single choke point for every way a coach tip can close -- the "Got
    /// it" button, clicking outside the popover, or Escape all end up here.
    /// Dismissing always means permanently: there's no more per-tip "show
    /// this again" opt-in, so any close drops the tip from the rotation for
    /// good (recoverable only via Preferences -> Activity -> Reset All Tips).
    private func dismissActiveCoachTip(_ tip: CoachTip) {
        preferences.dismissedCoachTips.insert(tip.rawValue)
        activeCoachTip = nil
        AnalyticsService.shared.track(.coachTipDismissed, properties: ["tip_id": tip.rawValue])
    }

    private func coachTipPopoverBinding(for tip: CoachTip) -> Binding<Bool> {
        Binding(
            get: { activeCoachTip == tip },
            set: { isPresented in
                if !isPresented { dismissActiveCoachTip(tip) }
            }
        )
    }

    @ViewBuilder
    private func coachTipBubble(for tip: CoachTip) -> some View {
        CoachTipBubble(
            message: tip.message(preferences: preferences),
            themeAccent: themeAccent,
            onDismiss: { dismissActiveCoachTip(tip) }
        )
    }

    private var header: some View {
        Text(headerTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.panelTextSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .popover(isPresented: $isShowingAnalyticsConsent) {
                AnalyticsConsentPrompt(themeAccent: themeAccent, onDecide: decideAnalyticsConsent)
            }
            .popover(isPresented: npsPopoverBinding) {
                NPSPromptView(themeAccent: themeAccent, onSubmit: submitNPS)
            }
    }

    /// Closing before ever picking a score (the "x", clicking outside,
    /// Escape) is a dismissal with nothing to submit -- NPSPromptView itself
    /// has no dismiss callback, since SwiftUI already routes every one of
    /// those paths through this binding's setter the same way CoachTip's
    /// binding does.
    private var npsPopoverBinding: Binding<Bool> {
        Binding(
            get: { isShowingNPSPrompt },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissNPSPrompt()
                }
                isShowingNPSPrompt = isPresented
            }
        )
    }

    private func submitNPS(score: Int, feedback: String?) {
        viewModel.submitNPS(score: score, feedback: feedback)
        isShowingNPSPrompt = false
    }

    // Debug builds only -- see DebugBuildTag.swift.
    private var headerTitle: String {
        #if DEBUG
        return "Squirrel Trap \(debugNextVersion)\(debugBuildTag)"
        #else
        return "Squirrel Trap"
        #endif
    }

    /// Quiet, always-visible -- no badges, no "you lost your streak" copy on
    /// a reset. When viewModel.isCelebrating fires (every task completed, not
    /// just streak-day extensions), runCelebrationAnimation() pulses the
    /// icon and today's-count number to 1.5x and back, entirely within
    /// celebrationDuration, then everything settles back on its own. The
    /// shrink/puff-cloud half of the celebration lives on the individual
    /// to-do row instead -- see PendingRowView.startCompletionAnimation.
    private var activitySummary: some View {
        let days = intentStore.currentStreak
        return HStack(spacing: 4) {
            if preferences.showStreak {
                Text("🔥")
                    .scaleEffect(iconScale)
                Text("\(days) day\(days == 1 ? "" : "s")")
                    .foregroundStyle(viewModel.isCelebrating ? themeAccent : Color.panelTextSecondary)
                Text("·")
                    .foregroundStyle(Color.panelTextSecondary)
            }
            Text("✓")
                .foregroundStyle(Color.panelTextSecondary)
            Text("\(intentStore.todayCompletedCount)")
                .foregroundStyle(Color.panelTextSecondary)
                .scaleEffect(countScale)
            Text("today")
                .foregroundStyle(Color.panelTextSecondary)
        }
        .font(.system(size: 10))
        .frame(maxWidth: .infinity, alignment: .center)
        .onChange(of: viewModel.isCelebrating) { _, newValue in
            if newValue { runCelebrationAnimation() }
        }
    }

    /// Timed as a fraction of celebrationDuration (see
    /// Core/CelebrationTiming.swift -- the one knob to tweak for pacing): the
    /// icon and today's-count number grow to 1.5x over the first half and
    /// shrink back over the second.
    private func runCelebrationAnimation() {
        let half = celebrationDuration / 2
        withAnimation(.easeOut(duration: half)) {
            iconScale = 1.5
            countScale = 1.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + half) {
            withAnimation(.easeIn(duration: half)) {
                iconScale = 1.0
                countScale = 1.0
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                // Dismiss any open coach-tip popover *before* navigating away
                // -- PanelController.setContent() removes this whole view
                // from the window to swap in Preferences, and doing that
                // while a popover anchored to it is still marked presented
                // left the popover's child window dangling, corrupting
                // Preferences' responder chain (Escape/dismiss stopped
                // working once you'd opened it that way).
                activeCoachTip = nil
                onOpenPreferences()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(themeAccent)
            }
            .buttonStyle(.plain)
            .help("Preferences")
            .accessibilityLabel("Preferences")
            .popover(isPresented: coachTipPopoverBinding(for: .preferences)) {
                coachTipBubble(for: .preferences)
            }
            // Reminders/Default Alarm aren't literally gear-icon features,
            // but there's no other always-present anchor in this footer to
            // hang a settings-adjacent tip on -- each only ever shows once,
            // at its own trigger count, so stacking a few here over time
            // reads as "more to discover" rather than repeated nagging.
            .popover(isPresented: coachTipPopoverBinding(for: .reminders)) {
                coachTipBubble(for: .reminders)
            }
            .popover(isPresented: coachTipPopoverBinding(for: .defaultAlarm)) {
                coachTipBubble(for: .defaultAlarm)
            }
            .popover(isPresented: coachTipPopoverBinding(for: .launchAtLogin)) {
                coachTipBubble(for: .launchAtLogin)
            }

            // Rapidly switching apps can turn the popup itself into the
            // annoyance — Snooze suppresses Cmd+Tab triggering it for a bit
            // (the menu bar icon and Cmd+, still work, and clicking the icon
            // cancels the snooze early). Duration is configured in Preferences;
            // the fade + "Snoozing…" message live in PanelController so both
            // this button and the one in Preferences share the same behavior.
            SnoozeButton(minutes: preferences.snoozeDurationMinutes) {
                activeCoachTip = nil
                onSnooze()
            }
            .help("Snooze Cmd+Tab for a while")
                .popover(isPresented: coachTipPopoverBinding(for: .snooze)) {
                    coachTipBubble(for: .snooze)
                }

            #if DEBUG
            // Debug-only: the real celebration only fires once per calendar
            // day, which makes tuning CelebrationTiming's duration
            // impractical without a way to re-fire it on demand.
            Button {
                viewModel.previewCelebration()
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(themeAccent)
            }
            .buttonStyle(.plain)
            .help("Preview celebration (debug only)")
            .accessibilityLabel("Preview celebration")
            #endif

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
                    .glassCard(tint: themeAccent)
                    .focused($isInputFocused)
                    .onSubmit { viewModel.submit(dismiss: onDismiss) }
            }

            Button {
                viewModel.isShowingFavorites.toggle()
            } label: {
                Image(systemName: viewModel.isShowingFavorites ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundStyle(viewModel.isShowingFavorites ? Color("SunnyYellow") : themeAccent.opacity(0.5))
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
                                themeAccent: themeAccent,
                                isHighlighted: entry.id == viewModel.highlightedEntryID,
                                onToggleCompleted: { viewModel.toggleCompleted(id: entry.id) },
                                onToggleFavorite: { intentStore.toggleFavorite(id: entry.id) },
                                onSetReminder: { duration in viewModel.setReminder(for: entry.id, duration: duration) },
                                onCancelReminder: { viewModel.cancelReminder(for: entry.id) },
                                onSetColor: { color in intentStore.setColor(id: entry.id, colorTag: color) },
                                onDrop: { draggedID in intentStore.movePendingEntry(id: draggedID, before: entry.id) },
                                onDragHandleHoverChanged: onDragHandleHoverChanged
                            )
                        }

                        // Every row above only offers "drop before me" — without
                        // this, there's no way to drag something to the very
                        // bottom of the pending list.
                        if !pendingEntries.isEmpty {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isEndDropTargeted ? themeAccent.opacity(0.24) : Color.clear)
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
                            HStack {
                                Text("Completed")
                                    .font(.caption)
                                    .foregroundStyle(Color.panelTextSecondary)

                                Spacer()

                                Button("clear all") {
                                    showingClearCompletedConfirm = true
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(Color.panelTextSecondary)
                                .confirmationDialog(
                                    "Delete all completed items? This can't be undone.",
                                    isPresented: $showingClearCompletedConfirm,
                                    titleVisibility: .visible
                                ) {
                                    Button("Delete Completed", role: .destructive) {
                                        viewModel.clearCompletedEntries()
                                    }
                                    Button("Cancel", role: .cancel) {}
                                }
                            }
                            .padding(.top, pendingEntries.isEmpty ? 0 : 4)

                            ForEach(completedEntries) { entry in
                                IntentRowView(
                                    entry: entry,
                                    themeAccent: themeAccent,
                                    onToggleCompleted: { viewModel.toggleCompleted(id: entry.id) },
                                    onToggleFavorite: { intentStore.toggleFavorite(id: entry.id) },
                                    onDelete: {
                                        intentStore.delete(id: entry.id)
                                        AnalyticsService.shared.track(.taskDeleted)
                                    }
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
                                            .foregroundStyle(themeAccent)
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
                                        .foregroundStyle(themeAccent)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from favorites")
                                .accessibilityLabel("Remove from favorites")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .glassCard(tint: themeAccent)
                        }
                    }
                }
            }
        }
    }
}
