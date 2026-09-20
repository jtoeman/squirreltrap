import AppKit
import SwiftUI

struct PreferencesSyncTab: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var cloudSyncEngine: CloudSyncEngine
    let intentStore: IntentStore
    var onOpenReminderSync: () -> Void
    var isOnboarding: Bool = false

    @State private var showCopiedConfirmation = false

    /// Hairline row separators, only between rows shown during onboarding --
    /// normal Preferences stays as a denser Grid with no dividers.
    @ViewBuilder
    private var onboardingDivider: some View {
        if isOnboarding {
            GridRow {
                Divider().gridCellColumns(2)
            }
        }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                HStack(spacing: 4) {
                    Text("iCloud Sync")
                        .foregroundStyle(Color.panelTextSecondary)
                        .lineLimit(1)
                    HelpTip("Keeps your to-do list in sync across every Mac you use, always both ways, via your own iCloud account -- not a third-party server.")
                }
                HStack(spacing: 6) {
                    Toggle("", isOn: $preferences.iCloudSyncEnabled)
                        .labelsHidden()
                        .onChange(of: preferences.iCloudSyncEnabled) { oldValue, newValue in
                            // Same reasoning as Reminders sync: flip the toggle on and
                            // wait for the every-Nth-show fallback (or a push that
                            // hasn't arrived yet) reads as "nothing happened" — sync
                            // right away instead, same as turning on Reminders sync
                            // immediately creates its dedicated list.
                            guard !oldValue, newValue else { return }
                            Task { await cloudSyncEngine.sync() }
                        }
                    if cloudSyncEngine.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else if preferences.iCloudSyncEnabled {
                        Button("Sync Now") {
                            Task { await cloudSyncEngine.sync() }
                        }
                        .controlSize(.small)
                    }
                    Spacer(minLength: 8)
                    Text(cloudSyncEngine.accountStatusDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.panelTextSecondary)
                }
            }

            if let lastSyncError = cloudSyncEngine.lastSyncError {
                GridRow {
                    Text("")
                    Text(lastSyncError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let lastSyncSummary = cloudSyncEngine.lastSyncSummary {
                GridRow {
                    Text("")
                    Text(lastSyncSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.panelTextSecondary)
                }
            }

            onboardingDivider

            GridRow {
                Text("")
                HStack(spacing: 4) {
                    Button("Reminders Sync…", action: onOpenReminderSync)
                    HelpTip("Optionally connects Squirrel Trap to a list in Apple's Reminders app, one-directional or both ways, your choice.")
                }
            }

            onboardingDivider

            GridRow {
                Text("")
                HStack(spacing: 8) {
                    Button("Export Open Items") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(intentStore.csvExport(), forType: .string)
                        // This only ever copies to the clipboard, silently -- with
                        // no confirmation it's indistinguishable from doing
                        // nothing at all. Same fix as the update-check status.
                        showCopiedConfirmation = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            showCopiedConfirmation = false
                        }
                    }
                    .help("Copies your open (not completed) items as CSV to the clipboard")
                    if showCopiedConfirmation {
                        Label("Copied", systemImage: "checkmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.panelTextSecondary)
                    }
                }
            }
        }
        .font(.system(size: 12))
        .onAppear { cloudSyncEngine.refreshAccountStatus() }
    }
}
