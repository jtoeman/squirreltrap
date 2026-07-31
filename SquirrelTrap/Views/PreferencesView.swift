import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var cloudSyncEngine: CloudSyncEngine
    @ObservedObject var updateChecker: UpdateChecker
    let intentStore: IntentStore
    let reminderScheduler: ReminderScheduler
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    @State private var permissionGranted = PermissionManager.status() == .granted
    @State private var selectedTab: PreferencesTab = .general
    // Local mirror of the General tab's confirmation-dialog state (owned there,
    // reported up here via onConfirmationActiveChanged) so onExitCommand below
    // can still avoid dismissing the whole panel while "Clear Finished/All
    // Items" is up — see the matching guard on PanelController's
    // suppressEscapeDismiss, which relies on the same callback.
    @State private var hasActiveConfirmation = false
    var onBack: () -> Void
    var onDismiss: () -> Void
    var onQuit: () -> Void
    var onConfirmationActiveChanged: (Bool) -> Void = { _ in }
    var onOpenReminderSync: () -> Void = {}
    var onSnooze: () -> Void = {}

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func handleConfirmationActiveChanged(_ active: Bool) {
        hasActiveConfirmation = active
        onConfirmationActiveChanged(active)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(alignment: .top, spacing: 14) {
                sidebar

                Divider()

                Group {
                    switch selectedTab {
                    case .general:
                        PreferencesGeneralTab(
                            preferences: preferences,
                            intentStore: intentStore,
                            reminderScheduler: reminderScheduler,
                            launchAtLoginEnabled: $launchAtLoginEnabled,
                            onConfirmationActiveChanged: handleConfirmationActiveChanged,
                            onQuit: onQuit
                        )
                    case .appearance:
                        PreferencesAppearanceTab(preferences: preferences, permissionGranted: $permissionGranted)
                    case .sync:
                        PreferencesSyncTab(
                            preferences: preferences,
                            cloudSyncEngine: cloudSyncEngine,
                            intentStore: intentStore,
                            onOpenReminderSync: onOpenReminderSync
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 10)
        .frame(width: 520, height: 460, alignment: .top)
        .onExitCommand { if !hasActiveConfirmation { onDismiss() } }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Squirrel Trap")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.panelTextPrimary)
            Text("Preferences")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.panelTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Left column: logo/version/update-check up top (always visible regardless
    /// of tab, since it lives here rather than inside any tab's content), then
    /// the tab list below it -- a vertical sidebar rather than a horizontal tab
    /// bar, matching the reference layout this was modeled on.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 108, height: 108)
                Text("v\(appVersionString)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.panelTextSecondary)
                updateStatus
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(PreferencesTab.allCases) { tab in
                    tabButton(tab)
                }
            }
        }
        .frame(width: 132, alignment: .leading)
    }

    /// Custom-styled rather than .pickerStyle(.segmented) or a native sidebar
    /// List -- both would pull in chrome that clashes with the translucent
    /// blue glass card look everywhere else in this app.
    private func tabButton(_ tab: PreferencesTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .frame(width: 14)
                Text(tab.label)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
            .foregroundStyle(selectedTab == tab ? Color.panelTextPrimary : Color.panelTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if selectedTab == tab {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.35))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// Persistent confirmation that a check actually happened, rather than a
    /// manual "Check for Updates" click silently reverting to itself with no
    /// visible feedback when nothing newer is found.
    @ViewBuilder
    private var updateStatus: some View {
        if updateChecker.isChecking {
            ProgressView()
                .controlSize(.mini)
        } else if let update = updateChecker.availableUpdate {
            Link("Update to v\(update.version)", destination: update.url)
                .font(.system(size: 10))
        } else if preferences.lastUpdateCheckAt != nil {
            VStack(spacing: 3) {
                Label("Up to date", systemImage: "checkmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.panelTextSecondary)
                Button("Check Again") {
                    Task { await updateChecker.check() }
                }
                .controlSize(.mini)
            }
        } else {
            Button("Check for Updates") {
                Task { await updateChecker.check() }
            }
            .controlSize(.mini)
        }
    }

    /// Mirrors the main panel's footer exactly: a utility icon at the bottom-left
    /// (gear there, back-chevron here), the Snooze button pinned at the same
    /// on-screen spot it occupies there too -- rather than living inside
    /// General's Grid where its position shifted with the row's own content --
    /// and the Ko-fi button at the bottom-right.
    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Back to Squirrel Trap")
            .accessibilityLabel("Back to Squirrel Trap")

            SnoozeButton(minutes: preferences.snoozeDurationMinutes, action: onSnooze)
                .help("Snooze Cmd+Tab for a while")

            Spacer()

            KofiButton(onOpened: onDismiss)
        }
    }
}
