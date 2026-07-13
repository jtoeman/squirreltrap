import AppKit
import Combine
import SwiftUI

/// NSPanel subclass so Escape (cancelOperation) reliably dismisses the panel
/// even when a SwiftUI text field inside it has focus and might otherwise
/// swallow onExitCommand.
final class DismissiblePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        FileHandle.standardError.write("Squirrel Trap DEBUG: [cancelOperation] AppKit cancelOperation fired\n".data(using: .utf8)!)
        onCancel?()
    }
}

@MainActor
final class PanelController: NSObject {
    private let intentStore: IntentStore
    private let preferences: AppPreferences
    private let reminderScheduler: ReminderScheduler
    private let promptViewModel: PromptPanelViewModel

    // The visible card is 420x340 (340 = 320 + one half-row, so an overflowing
    // list always leaves a partial next row peeking into view as a "there's more
    // below" cue instead of clipping cleanly at a full row boundary); the window
    // itself is padded out by cardMargin on every side so the close button can
    // sit outside the card's own corner without being clipped at the window edge.
    private let cardSize = NSSize(width: 420, height: 340)
    private let cardMargin: CGFloat = 20
    private var windowSize: NSSize {
        NSSize(width: cardSize.width + cardMargin * 2, height: cardSize.height + cardMargin * 2)
    }

    private var panel: DismissiblePanel?
    // The blur card and close button are plain AppKit views owned directly by the
    // window's contentView, not routed through SwiftUI. Embedding NSVisualEffectView
    // via a SwiftUI `.background()` modifier (even with isOpaque/backgroundColor
    // cleared) didn't reliably keep it as a live, blur-through layer — and swapping
    // `contentViewController` let NSHostingController's automatic content-size
    // negotiation quietly resize/reposition the window on every content swap.
    // Owning the chrome natively avoids both problems.
    private var effectView: NSVisualEffectView?
    // Shown instead of effectView when translucency is turned off in
    // Preferences. SwiftUI content lives in contentContainer, a separate
    // sibling view — not a child of effectView — so hiding the blur to show
    // this doesn't also hide the actual panel content.
    private var opaqueFallbackView: NSView?
    private var contentContainer: NSView?
    private var closeButton: NSButton?
    // A permanent color layer sitting above the material and below whatever
    // SwiftUI content is currently showing. The material alone just blurs
    // whatever's behind the window — on a warm/brown wallpaper that reads as
    // muddy, not blue. This overlay is what guarantees the panel always reads
    // as cool blue glass regardless of what's behind it.
    private var colorTintOverlay: NSView?
    private var currentHostingView: NSView?
    private var translucencyCancellable: AnyCancellable?

    // Reused across shows instead of recreated each time: recreating on every
    // Cmd+Tab (especially rapid repeats) raced SwiftUI's focus system against the
    // old view's teardown, producing "first responder in a different window"
    // warnings that AppKit flags as an eventual crash risk.
    private var promptHostingController: NSHostingController<PromptPanelView>?
    private var permissionHostingController: NSHostingController<PermissionRequestView>?
    private var preferencesHostingController: NSHostingController<PreferencesView>?
    private var globalClickMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    private var hasReclaimedFocusForCurrentShow = false
    var onQuit: (() -> Void)?
    // Lets the dismiss-on-any-non-text-key logic below tell a bare Cmd tap
    // (dismiss) apart from a real Cmd+Tab switch (never dismiss) — see
    // handlePotentialDismissKey. Wired by AppDelegate to AppSwitchMonitor,
    // which is the only thing with visibility into the real Cmd+Tab gesture
    // (via its own CGEventTap; a held Cmd key alone looks identical to us).
    var isSwitchGestureActive: (() -> Bool)?

    // Fades the panel out if you never interact with it, so an accidental or
    // half-considered Cmd+Tab doesn't just leave it sitting on screen forever.
    // Duration is user-configurable (AppPreferences.inactivityTimeout).
    private var dismissTimer: Timer?
    private var localActivityMonitor: Any?

    // Any non-text keyboard input (Escape, a Cmd/Control shortcut combo, or
    // just tapping Cmd/Option/Fn alone) dismisses the panel — the idea being
    // that reaching for any of those means your attention already moved on
    // from typing an intent. Shift and Cmd+Tab itself are the only exceptions.
    private var dismissKeyMonitor: Any?
    private var modifiersHeldAtRisk: NSEvent.ModifierFlags = []

    // Escape reliably dismisses the panel via DismissiblePanel.cancelOperation
    // (see that type's comment) — but that override fires at the AppKit level,
    // with no awareness of a SwiftUI confirmationDialog currently open on top.
    // Without this guard, hitting Escape to cancel "Clear All Items" closed
    // the whole panel *in addition to* the confirmation dialog, instead of
    // just canceling the dialog. PreferencesView flips this while a
    // confirmationDialog is presented.
    private var suppressEscapeDismiss = false

    init(intentStore: IntentStore, preferences: AppPreferences, reminderScheduler: ReminderScheduler) {
        self.intentStore = intentStore
        self.preferences = preferences
        self.reminderScheduler = reminderScheduler
        self.promptViewModel = PromptPanelViewModel(intentStore: intentStore, reminderScheduler: reminderScheduler)
        super.init()

        // Every Cmd+Tab ends with some other app's window becoming key — that's not
        // the user clicking away, it's the switch itself completing. Reclaim key focus
        // right after so the panel keeps the caret instead of self-dismissing.
        //
        // This must only happen for THAT ONE activation, not every subsequent app
        // activation while the panel happens to still be visible — logging showed
        // reclaiming unconditionally here fights any app the user deliberately
        // switches to afterward (e.g. Activity Monitor) for real key status,
        // sometimes leaving Escape/keystrokes going to the wrong app entirely.
        // hasReclaimedFocusForCurrentShow (reset in present()) limits it to once.
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "?"
            FileHandle.standardError.write("Squirrel Trap DEBUG: [didActivateApplication] \(app)\n".data(using: .utf8)!)
            guard let self, !self.hasReclaimedFocusForCurrentShow else { return }
            self.hasReclaimedFocusForCurrentShow = true
            self.reclaimKeyFocusIfVisible()
        }
    }

    deinit {
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        if let localActivityMonitor {
            NSEvent.removeMonitor(localActivityMonitor)
        }
        if let dismissKeyMonitor {
            NSEvent.removeMonitor(dismissKeyMonitor)
        }
        dismissTimer?.invalidate()
    }

    func showPromptPanel(highlighting entryID: UUID? = nil) {
        // Clear the draft/favorites-mode before the window appears, so there's no
        // flash of stale content — but the focus *trigger* below has to wait until
        // after present() actually makes the window key, otherwise SwiftUI applies
        // it to a not-yet-key window and the caret never actually lands.
        promptViewModel.reset(highlighting: entryID)
        _ = obtainPanel()
        let controller = promptHostingController ?? {
            let controller = NSHostingController(
                rootView: PromptPanelView(
                    viewModel: promptViewModel,
                    onDismiss: { [weak self] in self?.hidePanel() },
                    onEscape: { [weak self] in
                        FileHandle.standardError.write("Squirrel Trap DEBUG: [onExitCommand] SwiftUI onExitCommand fired\n".data(using: .utf8)!)
                        self?.handleCancelOperation()
                    },
                    onOpenPreferences: { [weak self] in self?.showPreferencesPanel() },
                    onDragHandleHoverChanged: { [weak self] hovering in
                        self?.panel?.isMovableByWindowBackground = !hovering
                    }
                )
            )
            promptHostingController = controller
            return controller
        }()
        setContent(controller.view)
        present()
        promptViewModel.focusToken = UUID()
    }

    func showPermissionRequestPanel() {
        _ = obtainPanel()
        let controller = permissionHostingController ?? {
            let controller = NSHostingController(
                rootView: PermissionRequestView(onDismiss: { [weak self] in self?.hidePanel() })
            )
            permissionHostingController = controller
            return controller
        }()
        setContent(controller.view)
        present()
    }

    func showPreferencesPanel() {
        _ = obtainPanel()
        let controller = preferencesHostingController ?? {
            let controller = NSHostingController(
                rootView: PreferencesView(
                    preferences: preferences,
                    intentStore: intentStore,
                    reminderScheduler: reminderScheduler,
                    onBack: { [weak self] in self?.showPromptPanel() },
                    onDismiss: { [weak self] in self?.hidePanel() },
                    onQuit: { [weak self] in self?.onQuit?() },
                    onConfirmationActiveChanged: { [weak self] active in self?.suppressEscapeDismiss = active }
                )
            )
            preferencesHostingController = controller
            return controller
        }()
        setContent(controller.view)
        present()
    }

    func hidePanel() {
        let stack = Thread.callStackSymbols.prefix(6).joined(separator: "\n  ")
        FileHandle.standardError.write("Squirrel Trap DEBUG: [hidePanel] called, panel.isVisible=\(panel?.isVisible ?? false)\n  \(stack)\n".data(using: .utf8)!)
        suppressEscapeDismiss = false
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        removeGlobalClickMonitor()
        stopActivityMonitoring()
        removeDismissKeyMonitor()
    }

    private func reclaimKeyFocusIfVisible() {
        guard let panel, panel.isVisible else {
            FileHandle.standardError.write("Squirrel Trap DEBUG: [reclaimKeyFocusIfVisible] skipped, panel.isVisible=\(panel?.isVisible ?? false)\n".data(using: .utf8)!)
            return
        }
        FileHandle.standardError.write("Squirrel Trap DEBUG: [reclaimKeyFocusIfVisible] reclaiming key focus\n".data(using: .utf8)!)
        panel.makeKeyAndOrderFront(nil)
        FileHandle.standardError.write("Squirrel Trap DEBUG: [reclaimKeyFocusIfVisible] after makeKeyAndOrderFront: isKeyWindow=\(panel.isKeyWindow), NSApp.isActive=\(NSApp.isActive)\n".data(using: .utf8)!)
    }

    /// Clicking into whatever app you switched to should dismiss the panel — but that
    /// click is delivered to a different app's window, not ours, so a local event
    /// handler can't see it. A global monitor is the only way to catch it.
    private func installGlobalClickMonitor() {
        removeGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.hidePanel()
            }
        }
    }

    private func removeGlobalClickMonitor() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
        globalClickMonitor = nil
    }

    /// A local monitor only sees events routed to our own app's windows, which is
    /// exactly "did the user touch this panel" — no extra permission needed, unlike
    /// the global click monitor above.
    private func startActivityMonitoring() {
        stopActivityMonitoring()
        // .leftMouseDragged matters on its own, not just .leftMouseDown — the
        // panel is draggable via isMovableByWindowBackground, and without it a
        // slow drag that outlasts the timeout would fade the window out mid-drag.
        localActivityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel, .mouseMoved]
        ) { [weak self] event in
            self?.registerActivity()
            return event
        }
        registerActivity()
    }

    private func installDismissKeyMonitor() {
        removeDismissKeyMonitor()
        modifiersHeldAtRisk = []
        dismissKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handlePotentialDismissKey(event)
            return event
        }
    }

    private func removeDismissKeyMonitor() {
        if let dismissKeyMonitor {
            NSEvent.removeMonitor(dismissKeyMonitor)
        }
        dismissKeyMonitor = nil
        modifiersHeldAtRisk = []
    }

    /// Escape and Cmd/Control combos dismiss immediately (any key pressed while
    /// Cmd/Control is held is clearly a shortcut, not typing — Option is exempt
    /// since Option+letter is how accented characters are typed). Bare taps of
    /// Cmd, Option, or Fn alone (held with nothing else pressed, then released)
    /// also dismiss, EXCEPT a bare Cmd tap that turns out to be the start of a
    /// real Cmd+Tab — isSwitchGestureActive is the only way to tell those apart,
    /// since the system consumes the Tab keydown before it ever reaches us.
    private func handlePotentialDismissKey(_ event: NSEvent) {
        guard !suppressEscapeDismiss, let panel, panel.isVisible else {
            FileHandle.standardError.write("Squirrel Trap DEBUG: [dismissKey] ignored (suppressEscapeDismiss=\(suppressEscapeDismiss), panelVisible=\(panel?.isVisible ?? false))\n".data(using: .utf8)!)
            return
        }
        let watched: NSEvent.ModifierFlags = [.command, .option, .function]

        switch event.type {
        case .keyDown:
            modifiersHeldAtRisk = []
            if event.keyCode == 53 {
                FileHandle.standardError.write("Squirrel Trap DEBUG: [dismissKey] keyDown Escape -> handleCancelOperation\n".data(using: .utf8)!)
                handleCancelOperation()
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            FileHandle.standardError.write("Squirrel Trap DEBUG: [dismissKey] keyDown keyCode=\(event.keyCode) flags=\(flags.rawValue)\n".data(using: .utf8)!)
            if flags.contains(.command) || flags.contains(.control) {
                FileHandle.standardError.write("Squirrel Trap DEBUG: [dismissKey] Cmd/Control combo -> handleCancelOperation\n".data(using: .utf8)!)
                handleCancelOperation()
            }

        case .flagsChanged:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let currentlyHeld = flags.intersection(watched)
            let wasHeld = modifiersHeldAtRisk
            FileHandle.standardError.write("Squirrel Trap DEBUG: [dismissKey] flagsChanged currentlyHeld=\(currentlyHeld.rawValue) wasHeld=\(wasHeld.rawValue)\n".data(using: .utf8)!)
            if currentlyHeld.isEmpty, !wasHeld.isEmpty {
                let wasRealSwitch = wasHeld.contains(.command) && (isSwitchGestureActive?() ?? false)
                FileHandle.standardError.write("Squirrel Trap DEBUG: [dismissKey] bare modifier released, wasRealSwitch=\(wasRealSwitch)\n".data(using: .utf8)!)
                if !wasRealSwitch {
                    handleCancelOperation()
                }
            } else {
                modifiersHeldAtRisk = currentlyHeld
            }

        default:
            break
        }
    }

    private func stopActivityMonitoring() {
        if let localActivityMonitor {
            NSEvent.removeMonitor(localActivityMonitor)
        }
        localActivityMonitor = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    /// Resets the countdown to the full (user-configurable) timeout.
    private func registerActivity() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: preferences.inactivityTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fadeOutAndHide()
            }
        }
    }

    private func fadeOutAndHide() {
        guard let panel, panel.isVisible else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            hidePanel()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.hidePanel()
        })
    }

    private func obtainPanel() -> DismissiblePanel {
        if let panel { return panel }

        let newPanel = DismissiblePanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        // .hudWindow material's live blur-through needs a vibrant-dark context to
        // render at all — this is also why the native switcher itself always looks
        // dark, regardless of your system light/dark setting.
        newPanel.appearance = NSAppearance(named: .vibrantDark)
        newPanel.hasShadow = true
        newPanel.hidesOnDeactivate = false
        // Off by default on every NSWindow — without this, .mouseMoved never
        // actually dispatches, so just moving the cursor (no click) wouldn't
        // count as activity for the undim/timeout logic.
        newPanel.acceptsMouseMovedEvents = true
        newPanel.isMovableByWindowBackground = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newPanel.isReleasedWhenClosed = false
        newPanel.onCancel = { [weak self] in self?.handleCancelOperation() }

        let baseView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        baseView.wantsLayer = true
        baseView.layer?.backgroundColor = .clear

        // Solid stand-in for the blur, added first so it sits behind effect —
        // only one of the two is ever visible at a time (see the
        // translucencyEnabled subscription below), toggled without touching
        // the SwiftUI content in contentContainer at all.
        let opaqueFallback = NSView(frame: NSRect(
            x: cardMargin, y: cardMargin, width: cardSize.width, height: cardSize.height
        ))
        opaqueFallback.wantsLayer = true
        opaqueFallback.layer?.backgroundColor = NSColor(red: 0x2A / 255, green: 0x3D / 255, blue: 0x63 / 255, alpha: 1).cgColor
        opaqueFallback.layer?.cornerRadius = 14
        opaqueFallback.layer?.masksToBounds = true
        baseView.addSubview(opaqueFallback)
        opaqueFallbackView = opaqueFallback

        let effect = NSVisualEffectView(frame: NSRect(
            x: cardMargin, y: cardMargin, width: cardSize.width, height: cardSize.height
        ))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        baseView.addSubview(effect)
        effectView = effect

        let tint = NSView(frame: effect.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(red: 0x24 / 255, green: 0x89 / 255, blue: 0xFF / 255, alpha: 0.13).cgColor
        tint.autoresizingMask = [.width, .height]
        effect.addSubview(tint)
        colorTintOverlay = tint

        // SwiftUI content's own container, stacked above both effect and
        // opaqueFallback — a sibling of both, not a child of effect, so
        // hiding effect to reveal opaqueFallback never hides the content too.
        let content = NSView(frame: NSRect(
            x: cardMargin, y: cardMargin, width: cardSize.width, height: cardSize.height
        ))
        content.wantsLayer = true
        content.layer?.backgroundColor = .clear
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = true
        baseView.addSubview(content)
        contentContainer = content

        let closeImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .regular))
        let closeBtn = NSButton(image: closeImage ?? NSImage(), target: self, action: #selector(closeButtonClicked))
        closeBtn.isBordered = false
        closeBtn.imageScaling = .scaleProportionallyUpOrDown
        closeBtn.contentTintColor = (NSColor(named: "AccentColor") ?? .controlAccentColor).withAlphaComponent(0.75)
        closeBtn.setAccessibilityLabel("Close")
        let closeButtonSize: CGFloat = 24
        closeBtn.frame = NSRect(
            x: cardMargin + cardSize.width - closeButtonSize / 2 - 2,
            y: windowSize.height - cardMargin - closeButtonSize / 2 - 2,
            width: closeButtonSize,
            height: closeButtonSize
        )
        baseView.addSubview(closeBtn)
        closeButton = closeBtn

        newPanel.contentView = baseView

        panel = newPanel

        // Diagnostic only: pinpoint the exact moment the panel silently loses
        // key status, independent of (and possibly not explained by) any
        // didActivateApplicationNotification we're already logging.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: newPanel, queue: .main
        ) { _ in
            FileHandle.standardError.write("Squirrel Trap DEBUG: [panel] didResignKey, NSApp.isActive=\(NSApp.isActive)\n".data(using: .utf8)!)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: newPanel, queue: .main
        ) { _ in
            FileHandle.standardError.write("Squirrel Trap DEBUG: [panel] didBecomeKey, NSApp.isActive=\(NSApp.isActive)\n".data(using: .utf8)!)
        }

        // Fires immediately with the current value on subscribe, so the
        // right view is showing from the very first present() — no extra
        // "apply initial state" call needed.
        translucencyCancellable = preferences.$translucencyEnabled.sink { [weak self] enabled in
            self?.effectView?.isHidden = !enabled
            self?.opaqueFallbackView?.isHidden = enabled
        }

        return newPanel
    }

    @objc private func closeButtonClicked() {
        FileHandle.standardError.write("Squirrel Trap DEBUG: [closeButtonClicked] X button clicked\n".data(using: .utf8)!)
        hidePanel()
    }

    private func handleCancelOperation() {
        FileHandle.standardError.write("Squirrel Trap DEBUG: [handleCancelOperation] suppressEscapeDismiss=\(suppressEscapeDismiss)\n".data(using: .utf8)!)
        guard !suppressEscapeDismiss else { return }
        hidePanel()
    }

    /// Swaps which SwiftUI content fills the card. Only removes the previously
    /// tracked hosting view — not every subview — so the permanent blue tint
    /// overlay underneath survives content swaps instead of being wiped each time.
    private func setContent(_ hostingView: NSView) {
        guard let contentContainer else { return }
        currentHostingView?.removeFromSuperview()
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.frame = contentContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentContainer.addSubview(hostingView)
        currentHostingView = hostingView
    }

    private func present() {
        let stack = Thread.callStackSymbols.prefix(6).joined(separator: "\n  ")
        FileHandle.standardError.write("Squirrel Trap DEBUG: [present] called\n  \(stack)\n".data(using: .utf8)!)
        guard let panel else { return }
        // Only reposition when the panel is opening fresh (Cmd+Tab, menu bar,
        // Cmd+,). Navigating between content within an already-visible panel
        // (gear -> Preferences, back -> prompt) should stay exactly where it is.
        if !panel.isVisible {
            positionOnActiveScreen(panel)
            hasReclaimedFocusForCurrentShow = false
        }
        panel.makeKeyAndOrderFront(nil)
        FileHandle.standardError.write("Squirrel Trap DEBUG: [present] after makeKeyAndOrderFront: isKeyWindow=\(panel.isKeyWindow), NSApp.isActive=\(NSApp.isActive)\n".data(using: .utf8)!)
        installGlobalClickMonitor()
        startActivityMonitoring()
        installDismissKeyMonitor()
    }

    /// Centers on whichever display currently has the mouse cursor, since that's
    /// the best proxy for "which screen the user is looking at" mid keyboard-switch.
    private func positionOnActiveScreen(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2 + 60
        )
        panel.setFrame(NSRect(origin: origin, size: windowSize), display: false)
    }
}
