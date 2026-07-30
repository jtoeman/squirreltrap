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
            tabBar

            HStack(alignment: .top, spacing: 16) {
                Group {
                    switch selectedTab {
                    case .general:
                        PreferencesGeneralTab(
                            preferences: preferences,
                            intentStore: intentStore,
                            reminderScheduler: reminderScheduler,
                            launchAtLoginEnabled: $launchAtLoginEnabled,
                            onConfirmationActiveChanged: handleConfirmationActiveChanged,
                            onQuit: onQuit,
                            onSnooze: onSnooze
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

                logoRail
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

    /// Custom-styled rather than .pickerStyle(.segmented) -- native macOS tab
    /// chrome would clash with the translucent blue glass card look everywhere
    /// else in this app.
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(PreferencesTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.label)
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? Color.panelTextPrimary : Color.panelTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.35))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    /// Sits beside whichever tab is selected, not inside any of them -- stays
    /// visible and in the same place regardless of tab.
    private var logoRail: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 100, height: 100)
            Text("v\(appVersionString)")
                .font(.system(size: 10))
                .foregroundStyle(Color.panelTextSecondary)
            if updateChecker.isChecking {
                ProgressView()
                    .controlSize(.mini)
            } else if let update = updateChecker.availableUpdate {
                Link("Update to v\(update.version)", destination: update.url)
                    .font(.system(size: 10))
            } else {
                Button("Check for Updates") {
                    Task { await updateChecker.check() }
                }
                .controlSize(.mini)
            }
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
