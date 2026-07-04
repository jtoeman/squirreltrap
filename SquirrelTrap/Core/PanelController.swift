import AppKit
import SwiftUI

/// NSPanel subclass so Escape (cancelOperation) reliably dismisses the panel
/// even when a SwiftUI text field inside it has focus and might otherwise
/// swallow onExitCommand.
final class DismissiblePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class PanelController: NSObject {
    private let intentStore: IntentStore
    private let preferences: AppPreferences
    private let promptViewModel: PromptPanelViewModel

    // The visible card is 420x320; the window itself is padded out by cardMargin
    // on every side so the close button can sit outside the card's own corner
    // without being clipped at the window edge.
    private let cardSize = NSSize(width: 420, height: 320)
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
    private var closeButton: NSButton?

    // Reused across shows instead of recreated each time: recreating on every
    // Cmd+Tab (especially rapid repeats) raced SwiftUI's focus system against the
    // old view's teardown, producing "first responder in a different window"
    // warnings that AppKit flags as an eventual crash risk.
    private var promptHostingController: NSHostingController<PromptPanelView>?
    private var permissionHostingController: NSHostingController<PermissionRequestView>?
    private var preferencesHostingController: NSHostingController<PreferencesView>?
    private var globalClickMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    var onQuit: (() -> Void)?

    init(intentStore: IntentStore, preferences: AppPreferences) {
        self.intentStore = intentStore
        self.preferences = preferences
        self.promptViewModel = PromptPanelViewModel(intentStore: intentStore)
        super.init()

        // Every Cmd+Tab ends with some other app's window becoming key — that's not
        // the user clicking away, it's the switch itself completing. Reclaim key focus
        // right after so the panel keeps the caret instead of self-dismissing.
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reclaimKeyFocusIfVisible()
        }
    }

    deinit {
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
    }

    func showPromptPanel() {
        promptViewModel.reset()
        _ = obtainPanel()
        let controller = promptHostingController ?? {
            let controller = NSHostingController(
                rootView: PromptPanelView(
                    viewModel: promptViewModel,
                    onDismiss: { [weak self] in self?.hidePanel() },
                    onOpenPreferences: { [weak self] in self?.showPreferencesPanel() }
                )
            )
            promptHostingController = controller
            return controller
        }()
        setContent(controller.view)
        present()
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
                    onBack: { [weak self] in self?.showPromptPanel() },
                    onDismiss: { [weak self] in self?.hidePanel() },
                    onQuit: { [weak self] in self?.onQuit?() }
                )
            )
            preferencesHostingController = controller
            return controller
        }()
        setContent(controller.view)
        present()
    }

    func hidePanel() {
        panel?.orderOut(nil)
        removeGlobalClickMonitor()
    }

    private func reclaimKeyFocusIfVisible() {
        guard let panel, panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
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
        newPanel.isMovableByWindowBackground = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newPanel.isReleasedWhenClosed = false
        newPanel.onCancel = { [weak self] in self?.hidePanel() }

        let baseView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        baseView.wantsLayer = true
        baseView.layer?.backgroundColor = .clear

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

        let closeImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .regular))
        let closeBtn = NSButton(image: closeImage ?? NSImage(), target: self, action: #selector(closeButtonClicked))
        closeBtn.isBordered = false
        closeBtn.imageScaling = .scaleProportionallyUpOrDown
        closeBtn.contentTintColor = .secondaryLabelColor
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
        return newPanel
    }

    @objc private func closeButtonClicked() {
        hidePanel()
    }

    /// Swaps which SwiftUI content fills the card. The hosting view is pinned to
    /// the card's exact bounds and never asked to auto-size the window itself.
    private func setContent(_ hostingView: NSView) {
        guard let effectView else { return }
        effectView.subviews.forEach { $0.removeFromSuperview() }
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)
    }

    private func present() {
        guard let panel else { return }
        // Only reposition when the panel is opening fresh (Cmd+Tab, menu bar,
        // Cmd+,). Navigating between content within an already-visible panel
        // (gear -> Preferences, back -> prompt) should stay exactly where it is.
        if !panel.isVisible {
            positionOnActiveScreen(panel)
        }
        panel.makeKeyAndOrderFront(nil)
        installGlobalClickMonitor()
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
