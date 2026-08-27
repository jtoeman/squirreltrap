import AppKit
import Combine
import SwiftUI
import UserNotifications
import WidgetKit

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
    private lazy var reminderSyncEngine = ReminderSyncEngine(intentStore: intentStore, preferences: preferences)
    private lazy var cloudSyncEngine = CloudSyncEngine(intentStore: intentStore, preferences: preferences)
    private lazy var updateChecker = UpdateChecker(preferences: preferences)

    private lazy var panelController = PanelController(
        intentStore: intentStore,
        preferences: preferences,
        reminderScheduler: reminderScheduler,
        reminderSyncEngine: reminderSyncEngine,
        cloudSyncEngine: cloudSyncEngine,
        updateChecker: updateChecker
    )
    private let monitor = AppSwitchMonitor()
    private let preferencesHotkey = PreferencesHotkeyMonitor()
    private var permissionPollTimer: Timer?
    private var heartbeatTimer: Timer?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var isPanelVisible = false
    private var snoozeExpiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two instances both loading entries.json into memory and later
        // calling IntentStore.save() independently is a silent last-writer-
        // wins race -- whichever instance saves second overwrites anything
        // the other one added or changed in between, with no error and no
        // way to recover it. Observed directly (an orphaned debug launch
        // coexisting with a fresh one); bail out before this instance's
        // IntentStore could ever be asked to save anything. Checked first,
        // before any other launch work, since intentStore.load() already
        // ran during this AppDelegate's property initialization above --
        // nothing has written to disk yet at this point either way, so
        // quitting here is always safe regardless of which instance wins.
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !otherInstances.isEmpty {
            debugLog("Squirrel Trap DEBUG: another instance is already running (pid \(otherInstances.map(\.processIdentifier))) -- quitting this one rather than risk a data-loss race on entries.json\n")
            NSApp.terminate(nil)
            return
        }

        panelController.onQuit = {
            NSApp.terminate(nil)
        }

        monitor.onSwitchGestureDetected = { [weak self] in
            guard let self else { return }
            debugLog("Squirrel Trap DEBUG: [onSwitchGestureDetected] snoozeUntil=\(String(describing: self.preferences.snoozeUntil)), now=\(Date())\n")
            // Snooze only suppresses the Cmd+Tab trigger -- the menu bar icon
            // and Cmd+, still open the panel normally.
            if let snoozeUntil = self.preferences.snoozeUntil, snoozeUntil > Date() {
                debugLog("Squirrel Trap DEBUG: [onSwitchGestureDetected] snoozed, suppressing show\n")
                return
            }
            self.panelController.showPromptPanel(viaSwitchGesture: true)
        }
        panelController.isSwitchGestureActive = { [weak monitor] in
            monitor?.switchDetectedDuringCurrentHold ?? false
        }
        panelController.onVisibilityChanged = { [weak self] visible in
            self?.isPanelVisible = visible
            self?.updateMenuBarAppearance()
        }
        preferences.$snoozeUntil
            .sink { [weak self] snoozeUntil in self?.handleSnoozeChanged(snoozeUntil) }
            .store(in: &cancellables)

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

        // Harmless to register even if iCloud sync is never turned on --
        // CloudSyncEngine itself gates all actual syncing on
        // preferences.iCloudSyncEnabled. Registering unconditionally at
        // launch means flipping the toggle on later doesn't need a relaunch.
        NSApp.registerForRemoteNotifications()
        cloudSyncEngine.refreshAccountStatus()

        Task { [updateChecker] in
            await updateChecker.checkIfDue()
        }

        preferences.$showMenuBarIcon
            .sink { [weak self] visible in self?.updateStatusItem(visible: visible) }
            .store(in: &cancellables)

        // Mirrors the consent toggle into the SDK immediately (covers both
        // the launch-time initial value and any later change from
        // AnalyticsConsentPrompt or the Preferences toggle) and keeps user
        // properties current for segmentation -- see AnalyticsService.
        AnalyticsService.shared.updateConsent(enabled: preferences.analyticsEnabled)
        AnalyticsService.shared.updateUserProperties(preferences: preferences)
        // Deliberately placed after updateConsent above -- the SDK is created
        // opted-out by default (see AnalyticsService.init), so tracking this
        // any earlier in launch would always be silently dropped, even for a
        // returning user who already granted consent last session.
        AnalyticsService.shared.track(.appLaunched)
        // A menu-bar app with launch-at-login can run for weeks between real
        // relaunches, so "check once at launch" alone would miss every day
        // after the first -- the hourly re-check is what actually catches
        // the day rolling over for a long-lived session.
        sendHeartbeatIfDue()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendHeartbeatIfDue() }
        }
        preferences.$analyticsEnabled
            .sink { enabled in AnalyticsService.shared.updateConsent(enabled: enabled) }
            .store(in: &cancellables)
        preferences.$panelTheme
            .sink { [weak self] _ in self?.refreshAnalyticsUserProperties() }
            .store(in: &cancellables)
        preferences.$showStreak
            .sink { [weak self] _ in self?.refreshAnalyticsUserProperties() }
            .store(in: &cancellables)
        preferences.$celebrationEnabled
            .sink { [weak self] _ in self?.refreshAnalyticsUserProperties() }
            .store(in: &cancellables)
        preferences.$defaultAlarmEnabled
            .sink { [weak self] _ in self?.refreshAnalyticsUserProperties() }
            .store(in: &cancellables)
        preferences.$showTips
            .sink { [weak self] _ in self?.refreshAnalyticsUserProperties() }
            .store(in: &cancellables)

        // Publishes a WidgetSnapshot to the shared App Group container
        // whenever entries or the panel theme change, so the desktop widget
        // stays current (including matching the chosen theme) without any
        // polling on its side.
        intentStore.$entries
            .sink { [weak self] _ in self?.publishWidgetSnapshot() }
            .store(in: &cancellables)
        preferences.$panelTheme
            .sink { [weak self] _ in self?.publishWidgetSnapshot() }
            .store(in: &cancellables)

        let status = PermissionManager.status()
        debugLog("Squirrel Trap DEBUG: launch status = \(status)\n")

        if status == .granted {
            let started = monitor.start()
            debugLog("Squirrel Trap DEBUG: monitor.start() = \(started)\n")
            // A fresh install that somehow already has permission (e.g.
            // reinstalling with permission retained) still gets onboarding,
            // shown proactively rather than waiting for a first Cmd+Tab.
            if !preferences.hasCompletedOnboarding {
                panelController.showOnboardingPanel()
            }
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
                debugLog("Squirrel Trap DEBUG: poll status = \(status)\n")
                guard status == .granted else { return }
                self.permissionPollTimer?.invalidate()
                self.permissionPollTimer = nil
                let started = self.monitor.start()
                debugLog("Squirrel Trap DEBUG: monitor.start() = \(started)\n")
                if !self.preferences.hasCompletedOnboarding {
                    self.panelController.showOnboardingPanel()
                } else {
                    self.panelController.hidePanel()
                }
            }
        }
    }

    private func refreshAnalyticsUserProperties() {
        AnalyticsService.shared.updateUserProperties(preferences: preferences)
    }

    /// Sends the Daily Heartbeat event at most once per calendar day,
    /// entirely regardless of user interaction -- see AnalyticsEvent's doc
    /// comment for why this exists. Gated the normal way: AnalyticsService's
    /// consent opt-out already suppresses this along with everything else,
    /// so no separate check is needed here.
    private func sendHeartbeatIfDue() {
        if let last = preferences.lastHeartbeatSentAt, Calendar.current.isDateInToday(last) {
            return
        }
        preferences.lastHeartbeatSentAt = Date()
        AnalyticsService.shared.track(.dailyHeartbeat, properties: [
            "current_streak": intentStore.currentStreak,
            "completed_today": intentStore.todayCompletedCount
        ])
    }

    private func publishWidgetSnapshot() {
        // Same order as the main panel's own pending list. Capped at 10 --
        // more than the largest widget size actually has room to show, and
        // the widget view itself trims further per its own family.
        let pendingTexts = intentStore.visibleEntries.filter { !$0.completed }.prefix(10).map(\.text)
        let snapshot = WidgetSnapshot(pendingItems: Array(pendingTexts), theme: preferences.panelTheme, generatedAt: Date())
        WidgetSnapshot.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func updateStatusItem(visible: Bool) {
        guard visible else {
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.setAccessibilityLabel("Squirrel Trap")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateMenuBarAppearance()
    }

    // Left click opens the same panel Cmd+Tab does (also canceling any active
    // snooze, since deliberately opening it yourself means you're done
    // avoiding it); right click surfaces the secondary actions (Preferences,
    // Quit) via a plain popped-up NSMenu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showStatusMenu(for: sender)
        } else {
            preferences.snoozeUntil = nil
            panelController.showPromptPanel()
        }
    }

    /// Menu bar icon reflects one of three states: the app icon while the
    /// panel is visible, a grayed-out default while snoozed, or the plain
    /// default otherwise.
    private func updateMenuBarAppearance() {
        guard let button = statusItem?.button else { return }
        if isPanelVisible {
            button.title = ""
            let icon = NSApp.applicationIconImage?.copy() as? NSImage
            icon?.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.alphaValue = 1.0
        } else {
            button.image = nil
            button.title = "🐿️"
            let isSnoozed = (preferences.snoozeUntil.map { $0 > Date() }) ?? false
            button.alphaValue = isSnoozed ? 0.35 : 1.0
        }
    }

    /// Snoozing doesn't need any background polling of its own — this timer
    /// only exists so the grayed-out icon visibly resets the moment a snooze
    /// naturally expires, instead of staying gray until the next click.
    private func handleSnoozeChanged(_ snoozeUntil: Date?) {
        snoozeExpiryTimer?.invalidate()
        snoozeExpiryTimer = nil
        if let snoozeUntil, snoozeUntil > Date() {
            snoozeExpiryTimer = Timer.scheduledTimer(withTimeInterval: snoozeUntil.timeIntervalSinceNow, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.preferences.snoozeUntil = nil
                }
            }
        }
        updateMenuBarAppearance()
    }

    private func showStatusMenu(for button: NSStatusBarButton) {
        let menu = NSMenu()

        let addItem = NSMenuItem(title: "Add Item", action: #selector(addItemMenuItemClicked), keyEquivalent: "")
        addItem.target = self
        addItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        menu.addItem(addItem)

        let snoozeMinutes = Int(preferences.snoozeDurationMinutes)
        let snoozeItem = NSMenuItem(title: "Snooze (\(snoozeMinutes)m)", action: #selector(snoozeMenuItemClicked), keyEquivalent: "")
        snoozeItem.target = self
        snoozeItem.image = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: nil)
        menu.addItem(snoozeItem)

        menu.addItem(.separator())

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

    // Same effect as a plain left-click on the menu bar icon: cancels any
    // active snooze (deliberately opening the panel yourself means you're
    // done avoiding it) and shows the quick-add panel.
    @objc private func addItemMenuItemClicked() {
        preferences.snoozeUntil = nil
        panelController.showPromptPanel()
    }

    // Same effect as clicking the in-panel Snooze button.
    @objc private func snoozeMenuItemClicked() {
        panelController.snoozeAndFadeOut()
    }

    @objc private func reminderMenuItemClicked(_ sender: NSMenuItem) {
        guard let entryID = sender.representedObject as? UUID else { return }
        panelController.showPromptPanel(highlighting: entryID)
    }

    // These three are what makes iCloud sync near-instant instead of only
    // running on the every-Nth-panel-show fallback: CloudKit's silent push
    // wakes the (already-running) app and hands it here.
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        debugLog("Squirrel Trap DEBUG: [push] registered for remote notifications\n")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        debugLog("Squirrel Trap DEBUG: [push] registration failed: \(error)\n")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        debugLog("Squirrel Trap DEBUG: [push] received remote notification\n")
        Task { [cloudSyncEngine] in
            await cloudSyncEngine.sync()
        }
    }

    // Covers Cmd+Q, the menu bar Quit item, and Preferences' Quit button (all
    // route through NSApp.terminate(nil), same as panelController.onQuit
    // above) -- not a hard kill, which never gives any process a chance to
    // run code at all.
    func applicationWillTerminate(_ notification: Notification) {
        AnalyticsService.shared.trackAppQuit()
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
