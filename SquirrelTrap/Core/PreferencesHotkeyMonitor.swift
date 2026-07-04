import AppKit

/// Cmd+, always works, even with the menu bar icon hidden — otherwise hiding the
/// icon would leave no way back into Preferences to turn it on again.
final class PreferencesHotkeyMonitor {
    private var monitor: Any?
    var onTriggered: (() -> Void)?

    func start() {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers == "," else { return }
            self?.onTriggered?()
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
