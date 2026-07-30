import SwiftUI

struct PreferencesGeneralTab: View {
    @ObservedObject var preferences: AppPreferences
    let intentStore: IntentStore
    let reminderScheduler: ReminderScheduler
    @Binding var launchAtLoginEnabled: Bool
    var onConfirmationActiveChanged: (Bool) -> Void
    var onQuit: () -> Void
    var onSnooze: () -> Void

    @State private var showingClearCompletedConfirm = false
    @State private var showingClearAllConfirm = false

    private var hasActiveConfirmation: Bool {
        showingClearCompletedConfirm || showingClearAllConfirm
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text("Launch at Login")
                    .foregroundStyle(Color.panelTextSecondary)
                Toggle("", isOn: $launchAtLoginEnabled)
                    .labelsHidden()
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                    }
            }

            GridRow {
                Text("Snooze for")
                    .foregroundStyle(Color.panelTextSecondary)
                HStack(spacing: 6) {
                    TimeoutComboBox(value: $preferences.snoozeDurationMinutes, options: [5, 10, 15, 30, 60])
                        .frame(width: 56)
                    Text("minutes")
                        .foregroundStyle(Color.panelTextSecondary)
                    Spacer(minLength: 12)
                    SnoozeButton(minutes: preferences.snoozeDurationMinutes, action: onSnooze)
                }
                .help("How long the Snooze button on the main panel suppresses Cmd+Tab for")
            }

            GridRow {
                Text("Auto-dismiss after")
                    .foregroundStyle(Color.panelTextSecondary)
                HStack(spacing: 6) {
                    TimeoutComboBox(value: $preferences.inactivityTimeout, options: [3, 5, 7, 10, 15, 20, 30])
                        .frame(width: 56)
                    Text("seconds")
                        .foregroundStyle(Color.panelTextSecondary)
                }
            }

            GridRow {
                Text("Default Alarm")
                    .foregroundStyle(Color.panelTextSecondary)
                HStack(spacing: 6) {
                    Toggle("", isOn: $preferences.defaultAlarmEnabled)
                        .labelsHidden()
                        .help("New to-dos automatically get a reminder set")
                    if preferences.defaultAlarmEnabled {
                        Picker("", selection: $preferences.defaultAlarmDurationSeconds) {
                            ForEach(IntentRowView.reminderDurations, id: \.seconds) { duration in
                                Text(duration.label).tag(duration.seconds)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            GridRow {
                Text("")
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
            }

            GridRow {
                Text("")
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

            GridRow {
                Text("")
                Button("Quit Squirrel Trap", role: .destructive, action: onQuit)
            }
        }
        .font(.system(size: 12))
        .onChange(of: showingClearCompletedConfirm) { _, _ in onConfirmationActiveChanged(hasActiveConfirmation) }
        .onChange(of: showingClearAllConfirm) { _, _ in onConfirmationActiveChanged(hasActiveConfirmation) }
    }
}
