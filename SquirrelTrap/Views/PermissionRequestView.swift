import SwiftUI

struct PermissionRequestView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Input Monitoring Needed")
                .font(.headline)

            Text("Squirrel Trap watches for the Cmd+Tab key combination to show a quick prompt when you switch apps. It does not record any other keystrokes.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Button("Not Now", action: onDismiss)
                Spacer()
                Button("Grant Access") {
                    PermissionManager.requestAccessOrOpenSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 320, alignment: .top)
        .onExitCommand(perform: onDismiss)
    }
}
