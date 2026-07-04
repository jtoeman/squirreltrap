import AppKit
import IOKit.hid

enum InputMonitoringStatus {
    case granted
    case denied
    case notDetermined
}

enum PermissionManager {
    static func status() -> InputMonitoringStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .notDetermined
        }
    }

    /// Triggers the system TCC prompt. Only works before the user has made a decision;
    /// once denied, macOS won't re-prompt and we must deep-link to System Settings instead.
    /// Activating first matters: this app never calls NSApp.activate elsewhere (so the
    /// floating panel never steals focus), but without being the active app at least
    /// momentarily here, the system consent prompt can fail to attribute to us at all.
    static func requestAccess() {
        NSApp.activate(ignoringOtherApps: true)
        let result = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        FileHandle.standardError.write(
            "Squirrel Trap DEBUG: IOHIDRequestAccess returned \(result), status now \(status())\n".data(using: .utf8)!
        )
    }

    static func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Always attempt the real request AND open Settings, unconditionally and every
    /// time — IOHIDRequestAccess's effect on the TCC list isn't reliably synchronous,
    /// so gating the Settings-open on an immediate status() re-check was itself racy.
    static func requestAccessOrOpenSettings() {
        requestAccess()
        openInputMonitoringSettings()
    }
}
