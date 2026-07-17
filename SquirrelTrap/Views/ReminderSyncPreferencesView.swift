import EventKit
import SwiftUI

/// A separate page from the main PreferencesView (which is a fixed 420x340
/// with no scrolling and already tightly packed) reached via a "Reminders
/// Sync…" button there, swapped into the same physical panel the same way
/// Preferences/Prompt already swap content.
struct ReminderSyncPreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    let syncEngine: ReminderSyncEngine
    var onBack: () -> Void

    @State private var availableLists: [EKCalendar] = []
    @State private var isLoadingLists = false
    @State private var accessDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(alignment: .leading, spacing: 6) {
                Text("Sync direction")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.panelTextPrimary)
                Picker("", selection: $preferences.reminderSyncDirection) {
                    ForEach(ReminderSyncDirection.allCases, id: \.self) { direction in
                        Text(direction.label).tag(direction)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .font(.system(size: 12))

            HStack(spacing: 6) {
                Text("Sync every")
                    .foregroundStyle(Color.panelTextSecondary)
                TextField("", value: $preferences.reminderSyncEveryNInvocations, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 40)
                Text("times the panel shows")
                    .foregroundStyle(Color.panelTextSecondary)
            }
            .font(.system(size: 12))

            Divider()

            listPicker

            Text("Only the task text and done/not-done status sync — no due dates, no favorites, no in-app reminder timers.")
                .font(.system(size: 11))
                .foregroundStyle(Color.panelTextSecondary)

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 10)
        .frame(width: 420, height: 340, alignment: .top)
        .onExitCommand(perform: onBack)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Squirrel Trap")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.panelTextPrimary)
            Text("Reminders Sync")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.panelTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var listPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Reminders list")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.panelTextPrimary)
                Spacer()
                Button(availableLists.isEmpty ? "Load Lists…" : "Refresh") {
                    Task { await loadLists() }
                }
                .controlSize(.small)
            }

            if isLoadingLists {
                ProgressView()
                    .controlSize(.small)
            } else if accessDenied {
                Text("Reminders access was denied. Enable it in System Settings → Privacy & Security → Reminders, then try again.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.panelTextSecondary)
            } else if !availableLists.isEmpty {
                Picker("", selection: $preferences.reminderSyncListIdentifier) {
                    Text("None").tag(String?.none)
                    ForEach(availableLists, id: \.calendarIdentifier) { calendar in
                        Text(calendar.title).tag(String?.some(calendar.calendarIdentifier))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } else if preferences.reminderSyncListIdentifier != nil {
                Text("Using a previously chosen list — tap Load Lists to change it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.panelTextSecondary)
            } else {
                Text("No list chosen yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.panelTextSecondary)
            }
        }
        .font(.system(size: 12))
    }

    private func loadLists() async {
        isLoadingLists = true
        let granted = await syncEngine.requestAccess()
        isLoadingLists = false
        guard granted else {
            accessDenied = true
            return
        }
        accessDenied = false
        availableLists = syncEngine.availableLists()
    }

    private var footer: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Back to Preferences")
            .accessibilityLabel("Back to Preferences")

            Spacer()
        }
    }
}
