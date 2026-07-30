import SwiftUI

struct PreferencesAppearanceTab: View {
    @ObservedObject var preferences: AppPreferences
    @Binding var permissionGranted: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text("Show menu bar icon")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
                Toggle("", isOn: $preferences.showMenuBarIcon)
                    .labelsHidden()
                    .help("Cmd+, always reopens Preferences, even with the icon hidden")
            }

            GridRow {
                Text("Enable translucency")
                    .foregroundStyle(Color.panelTextSecondary)
                    .lineLimit(1)
                Toggle("", isOn: $preferences.translucencyEnabled)
                    .labelsHidden()
                    .help("Turns off the frosted-glass blur for a solid card, independent of the system-wide Reduce Transparency setting")
            }

            GridRow {
                Text("")
                permissionStatus
            }
        }
        .font(.system(size: 12))
        .onAppear { permissionGranted = PermissionManager.status() == .granted }
    }

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
}
