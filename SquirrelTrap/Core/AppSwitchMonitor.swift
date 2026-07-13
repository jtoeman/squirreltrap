import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Listen-only observer for the Cmd+Tab gesture. Never modifies or consumes events —
/// the native app switcher keeps working exactly as it always has. Fires
/// `onSwitchGestureDetected` exactly once per Cmd-hold session, even if the user taps
/// Tab repeatedly to cycle through several apps, by tracking Cmd release via flagsChanged.
final class AppSwitchMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isGestureActive = false
    private var wasCommandHeld = false

    private let tabKeyCode = CGKeyCode(kVK_Tab)

    var onSwitchGestureDetected: (() -> Void)?

    /// True if a real Cmd+Tab was seen at any point during the Cmd key's
    /// *current* hold — reset only when Cmd is freshly pressed down, so a
    /// reader checking this right as Cmd is released still sees whether this
    /// hold included a switch, unaffected by isGestureActive resetting at
    /// that same release moment. Lets PanelController tell a bare Cmd tap
    /// apart from a real Cmd+Tab, which it otherwise can't — the Tab keydown
    /// of a real switch is consumed by the system switcher before any local
    /// event monitor ever sees it.
    private(set) var switchDetectedDuringCurrentHold = false

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: appSwitchMonitorEventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isGestureActive = false
    }

    fileprivate func handleTapEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            FileHandle.standardError.write("Squirrel Trap DEBUG: tap disabled (\(type)), re-enabling\n".data(using: .utf8)!)
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let commandHeld = event.flags.contains(.maskCommand)

        switch type {
        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard commandHeld, keyCode == tabKeyCode, !isGestureActive else { return }
            isGestureActive = true
            switchDetectedDuringCurrentHold = true
            FileHandle.standardError.write("Squirrel Trap DEBUG: gesture detected, firing callback\n".data(using: .utf8)!)
            let callback = onSwitchGestureDetected
            DispatchQueue.main.async {
                callback?()
            }

        case .flagsChanged:
            if commandHeld, !wasCommandHeld {
                switchDetectedDuringCurrentHold = false
            }
            wasCommandHeld = commandHeld
            if isGestureActive && !commandHeld {
                isGestureActive = false
            }

        default:
            break
        }
    }
}

private func appSwitchMonitorEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let monitor = Unmanaged<AppSwitchMonitor>.fromOpaque(refcon).takeUnretainedValue()
        monitor.handleTapEvent(type: type, event: event)
    }
    return Unmanaged.passRetained(event)
}
