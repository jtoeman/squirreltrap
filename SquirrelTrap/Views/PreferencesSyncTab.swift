import AppKit
import SwiftUI

struct PreferencesSyncTab: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var cloudSyncEngine: CloudSyncEngine
    let intentStore: IntentStore
    var onOpenReminderSync: () -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text("iCloud Sync")
                    .foregroundStyle(Color.panelTextSecondary)
                HStack(spacing: 6) {
                    Toggle("", isOn: $preferences.iCloudSyncEnabled)
                        .labelsHidden()
                        .help("Keep your to-do list in sync across your Macs via iCloud — always both ways")
                        .onChange(of: preferences.iCloudSyncEnabled) { oldValue, newValue in
                            // Same reasoning as Reminders sync: flip the toggle on and
                            // wait for the every-Nth-show fallback (or a push that
                            // hasn't arrived yet) reads as "nothing happened" — sync
                            // right away instead, same as turning on Reminders sync
                            // immediately forces a list load.
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

            GridRow {
                Text("")
                Button("Reminders Sync…", action: onOpenReminderSync)
                    .help("Optionally sync with a Reminders list")
            }

            GridRow {
                Text("")
                Button("Export Open Items") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(intentStore.csvExport(), forType: .string)
                }
                .help("Copies your open (not completed) items as CSV to the clipboard")
            }
        }
        .font(.system(size: 12))
        .onAppear { cloudSyncEngine.refreshAccountStatus() }
    }
}
