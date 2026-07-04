import AppKit
import Combine
import SwiftUI

@main
struct SquirrelTrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No real windows of our own — everything is driven by NSStatusItem/NSPanel
        // in AppDelegate. This just satisfies the App protocol's Scene requirement.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let intentStore = IntentStore()
    let preferences = AppPreferences()

    private lazy var panelController = PanelController(intentStore: intentStore, preferences: preferences)
    private let monitor = AppSwitchMonitor()
    private let preferencesHotkey = PreferencesHotkeyMonitor()
    private var permissionPollTimer: Timer?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController.onQuit = {
            NSApp.terminate(nil)
        }

        monitor.onSwitchGestureDetected = { [weak self] in
            self?.panelController.showPromptPanel()
        }

        preferencesHotkey.onTriggered = { [weak self] in
            self?.panelController.showPreferencesPanel()
        }
        preferencesHotkey.start()

        preferences.$showMenuBarIcon
            .sink { [weak self] visible in self?.updateStatusItem(visible: visible) }
            .store(in: &cancellables)

        let status = PermissionManager.status()
        FileHandle.standardError.write("Squirrel Trap DEBUG: launch status = \(status)\n".data(using: .utf8)!)

        if status == .granted {
            let started = monitor.start()
            FileHandle.standardError.write("Squirrel Trap DEBUG: monitor.start() = \(started)\n".data(using: .utf8)!)
        } else {
            panelController.showPermissionRequestPanel()
            startPermissionPolling()
        }
    }

    private func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let status = PermissionManager.status()
                FileHandle.standardError.write("Squirrel Trap DEBUG: poll status = \(status)\n".data(using: .utf8)!)
                guard status == .granted else { return }
                self.permissionPollTimer?.invalidate()
                self.permissionPollTimer = nil
                let started = self.monitor.start()
                FileHandle.standardError.write("Squirrel Trap DEBUG: monitor.start() = \(started)\n".data(using: .utf8)!)
                self.panelController.hidePanel()
            }
        }
    }

    private func updateStatusItem(visible: Bool) {
        guard visible else {
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.left.arrow.right.circle", accessibilityDescription: "Squirrel Trap")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    // Left click opens the same panel Cmd+Tab does; right click surfaces the
    // secondary actions (Preferences, Quit) via a plain popped-up NSMenu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showStatusMenu(for: sender)
        } else {
            panelController.showPromptPanel()
        }
    }

    private func showStatusMenu(for button: NSStatusBarButton) {
        let menu = NSMenu()

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferencesFromStatusMenu), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Squirrel Trap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func openPreferencesFromStatusMenu() {
        panelController.showPreferencesPanel()
    }
}
