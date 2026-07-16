import AppKit
import Combine
import SwiftUI
import UserNotifications

@main
struct SquirrelTrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No real windows of our own — everything is driven by NSStatusItem/NSPanel
        // in AppDelegate. A bare `Settings { }` scene silently binds Cmd+, to its
        // own empty native window, firing alongside our own PreferencesHotkeyMonitor.
        // Swapping to WindowGroup (which auto-opens at launch, unlike Settings) to
        // dodge that traded one bug for another — a black window flashing at every
        // launch, and SwiftUI's own window-creation/teardown machinery fighting with
        // our panel's focus timing. Settings never auto-opens; stripping its default
        // "Preferences…" command below removes the Cmd+, binding without any of that.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let intentStore = IntentStore()
    let preferences = AppPreferences()
    let reminderScheduler = ReminderScheduler()

    private lazy var panelController = PanelController(
        intentStore: intentStore,
        preferences: preferences,
        reminderScheduler: reminderScheduler
    )
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
        panelController.isSwitchGestureActive = { [weak monitor] in
            monitor?.switchDetectedDuringCurrentHold ?? false
        }

        preferencesHotkey.onTriggered = { [weak self] in
            self?.panelController.showPreferencesPanel()
        }
        preferencesHotkey.start()

        // A reminder firing calls back with the entry ID — same panel Cmd+Tab
        // uses, just with that specific task highlighted so it's unmistakable
        // which one the reminder was for. Also posts a native banner/sound,
        // same as how the built-in macOS Timer app announces completion.
        reminderScheduler.onFire = { [weak self] entryID in
            guard let self else { return }
            let taskText = self.intentStore.entries.first { $0.id == entryID }?.text
            self.intentStore.setReminder(id: entryID, date: nil)
            self.postReminderNotification(taskText: taskText)
            self.panelController.showPromptPanel(highlighting: entryID)
        }
        // Timers don't survive a quit — re-derive them from what's persisted so
        // a reminder set before the app was quit still fires (immediately, if
        // its time already passed while the app was closed).
        reminderScheduler.restore(from: intentStore.entries)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

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
        item.button?.title = "🐿️"
        item.button?.setAccessibilityLabel("Squirrel Trap")
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

        let activeReminders = intentStore.entriesWithActiveReminders
            .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
        if !activeReminders.isEmpty {
            let header = NSMenuItem(title: "Reminders", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for entry in activeReminders {
                guard let reminderDate = entry.reminderDate else { continue }
                let remaining = max(Int(reminderDate.timeIntervalSinceNow), 0)
                let title = "\(entry.text) — \(remaining / 60):\(String(format: "%02d", remaining % 60))"
                let item = NSMenuItem(title: title, action: #selector(reminderMenuItemClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.id
                menu.addItem(item)
            }

            menu.addItem(.separator())
        }

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

    @objc private func reminderMenuItemClicked(_ sender: NSMenuItem) {
        guard let entryID = sender.representedObject as? UUID else { return }
        panelController.showPromptPanel(highlighting: entryID)
    }

    private func postReminderNotification(taskText: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Squirrel Trap Reminder"
        content.body = taskText ?? "Time to check your task"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
