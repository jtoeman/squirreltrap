import SwiftUI

/// A separate page from the main PreferencesView (which is a fixed 420x340
/// with no scrolling and already tightly packed) reached via a "Reminders
/// Sync…" button there, swapped into the same physical panel the same way
/// Preferences/Prompt already swap content.
struct ReminderSyncPreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var syncEngine: ReminderSyncEngine
    var onBack: () -> Void

    @State private var listSetupFailed = false

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
                .onChange(of: preferences.reminderSyncDirection) { oldValue, newValue in
                    // Turning sync on for the first time creates the
                    // dedicated "Squirrel Trap" list right away (rather than
                    // waiting for the next sync attempt) so the permission
                    // prompt, and any list-creation failure, surface
                    // immediately instead of silently no-op'ing later.
                    guard oldValue == .off, newValue != .off else { return }
                    Task {
                        listSetupFailed = await syncEngine.dedicatedListOrCreate() == nil
                    }
                }
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

            listStatus

            HStack(spacing: 6) {
                Button("Sync Now") {
                    Task { await syncEngine.sync() }
                }
                .controlSize(.small)
                .disabled(preferences.reminderSyncDirection == .off || syncEngine.isSyncing)

                if syncEngine.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing Reminders…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.panelTextSecondary)
                }
            }

            Text("Only the task text and done/not-done status sync — no due dates, no favorites, no in-app reminder timers.")
                .font(.system(size: 11))
                .foregroundStyle(Color.panelTextSecondary)

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 10)
        .frame(width: 520, height: 460, alignment: .top)
        .onExitCommand(perform: onBack)
        .onAppear {
            // Catches access having been revoked since sync was turned on --
            // the onChange handler above only fires the moment direction
            // flips from off, not on every later visit to this screen.
            // Skipped entirely while sync is off so just viewing
            // Preferences never forces the permission prompt.
            guard preferences.reminderSyncDirection != .off else { return }
            Task {
                listSetupFailed = await syncEngine.dedicatedListOrCreate() == nil
            }
        }
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
    private var listStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reminders list")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.panelTextPrimary)

            if listSetupFailed {
                Text("Reminders access was denied. Enable it in System Settings → Privacy & Security → Reminders, then try again.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.panelTextSecondary)
            } else {
                Text("Always a private \"Squirrel Trap\" list, created automatically just for this app -- there's no other list to choose.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.panelTextSecondary)
            }
        }
        .font(.system(size: 12))
    }

    private var footer: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13))
                    .foregroundStyle(preferences.panelTheme.accent)
            }
            .buttonStyle(.plain)
            .help("Back to Preferences")
            .accessibilityLabel("Back to Preferences")

            Spacer()
        }
    }
}
