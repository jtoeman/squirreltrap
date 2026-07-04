import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    @State private var permissionGranted = PermissionManager.status() == .granted
    var onBack: () -> Void
    var onDismiss: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Text("Preferences")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Back to Squirrel Trap")

                    Spacer()
                }
            }

            if permissionGranted {
                Label("Watching for Cmd+Tab", systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Button("Grant Input Monitoring Access…") {
                    PermissionManager.requestAccessOrOpenSettings()
                }
            }

            Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)
                .help("Cmd+, always reopens Preferences, even with the icon hidden")

            Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                .onChange(of: launchAtLoginEnabled) { _, newValue in
                    LaunchAtLoginManager.setEnabled(newValue)
                }

            Spacer()

            HStack {
                KofiButton(onOpened: onDismiss)
                Spacer()
                Button("Quit Squirrel Trap", role: .destructive, action: onQuit)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 10)
        .frame(width: 420, height: 320, alignment: .top)
        .onExitCommand(perform: onDismiss)
        .onAppear { permissionGranted = PermissionManager.status() == .granted }
    }
}
