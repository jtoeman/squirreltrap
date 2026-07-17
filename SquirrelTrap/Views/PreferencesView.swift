import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    let intentStore: IntentStore
    let reminderScheduler: ReminderScheduler
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    @State private var permissionGranted = PermissionManager.status() == .granted
    @State private var showingClearCompletedConfirm = false
    @State private var showingClearAllConfirm = false
    var onBack: () -> Void
    var onDismiss: () -> Void
    var onQuit: () -> Void
    var onConfirmationActiveChanged: (Bool) -> Void = { _ in }
    var onOpenReminderSync: () -> Void = {}
    var onSnooze: () -> Void = {}

    // Escape while "Clear Finished/All Items" is up should cancel just that
    // confirmation, not the whole panel too — see the matching guard on
    // PanelController's suppressEscapeDismiss.
    private var hasActiveConfirmation: Bool {
        showingClearCompletedConfirm || showingClearAllConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            // Sharing a row (rather than an .overlay) puts permissionStatus at the
            // same top edge as this toggle for free, via plain HStack alignment —
            // no manual offset math, and no risk of the kind of layout-recursion
            // warning an .overlay(.frame(maxWidth: .infinity)) combo could trigger.
            HStack(alignment: .top) {
                Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)
                    .help("Cmd+, always reopens Preferences, even with the icon hidden")
                Spacer(minLength: 8)
                permissionStatus
            }

            HStack {
                Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                    }
                Spacer(minLength: 8)
                Toggle("Enable translucency", isOn: $preferences.translucencyEnabled)
                    .help("Turns off the frosted-glass blur for a solid card, independent of the system-wide Reduce Transparency setting")
            }

            HStack(spacing: 6) {
                Text("Auto-dismiss after")
                    .foregroundStyle(Color.panelTextSecondary)
                TimeoutComboBox(value: $preferences.inactivityTimeout, options: [3, 5, 7, 10, 15, 20, 30])
                    .frame(width: 56)
                Text("seconds")
                    .foregroundStyle(Color.panelTextSecondary)
            }
            .font(.system(size: 12))

            HStack(spacing: 6) {
                Text("Snooze for")
                    .foregroundStyle(Color.panelTextSecondary)
                TimeoutComboBox(value: $preferences.snoozeDurationMinutes, options: [5, 10, 15, 30, 60])
                    .frame(width: 56)
                Text("minutes")
                    .foregroundStyle(Color.panelTextSecondary)
                Spacer(minLength: 8)
                SnoozeButton(action: onSnooze)
            }
            .font(.system(size: 12))
            .help("How long the Snooze button on the main panel suppresses Cmd+Tab for")

            Divider()
                .padding(.top, 16)

            // The logo sits beside the button stack, top-aligned with the first
            // one, instead of below it — stacking it below (even inside a
            // ScrollView) kept needing more vertical room than this fixed-height
            // panel actually has, forcing a scrollbar no matter how things were
            // padded. Side-by-side fits everything without scrolling at all.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Button("Export Open Items") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(intentStore.csvExport(), forType: .string)
                    }
                    .help("Copies your open (not completed) items as CSV to the clipboard")

                    Button("Reminders Sync…", action: onOpenReminderSync)
                        .help("Optionally sync with a Reminders list")

                    Button("Clear Finished Items", role: .destructive) {
                        showingClearCompletedConfirm = true
                    }
                    .confirmationDialog(
                        "Delete all completed items? This can't be undone.",
                        isPresented: $showingClearCompletedConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Completed", role: .destructive) {
                            for id in intentStore.clearCompleted() {
                                reminderScheduler.cancel(for: id)
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }

                    Button("Clear All Items", role: .destructive) {
                        showingClearAllConfirm = true
                    }
                    .confirmationDialog(
                        "Delete your entire task history? This can't be undone.",
                        isPresented: $showingClearAllConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Everything", role: .destructive) {
                            for id in intentStore.clearAll() {
                                reminderScheduler.cancel(for: id)
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }

                Spacer()

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 100, height: 100)
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 10)
        .frame(width: 420, height: 400, alignment: .top)
        .onExitCommand { if !hasActiveConfirmation { onDismiss() } }
        .onAppear { permissionGranted = PermissionManager.status() == .granted }
        .onChange(of: showingClearCompletedConfirm) { _, _ in onConfirmationActiveChanged(hasActiveConfirmation) }
        .onChange(of: showingClearAllConfirm) { _, _ in onConfirmationActiveChanged(hasActiveConfirmation) }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Squirrel Trap")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.panelTextPrimary)
                Text("Preferences")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.panelTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                Button("Quit Squirrel Trap", role: .destructive, action: onQuit)
                    .controlSize(.small)
            }
        }
    }

    // Sits to the right, below "Quit Squirrel Trap" (same trailing edge) — see
    // the .overlay(alignment: .topTrailing) on the "Show menu bar icon" toggle.
    @ViewBuilder
    private var permissionStatus: some View {
        if permissionGranted {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Color.accentColor)
                Text("Watching for Cmd+Tab")
                    .foregroundStyle(Color.panelTextSecondary)
            }
            .font(.system(size: 11))
        } else {
            Button("Grant Input Monitoring Access…") {
                PermissionManager.requestAccessOrOpenSettings()
            }
            .controlSize(.small)
        }
    }

    /// Mirrors the main panel's footer exactly: a utility icon at the bottom-left
    /// (gear there, back-chevron here) and the Ko-fi button at the bottom-right.
    private var footer: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Back to Squirrel Trap")
            .accessibilityLabel("Back to Squirrel Trap")

            Spacer()

            KofiButton(onOpened: onDismiss)
        }
    }
}
