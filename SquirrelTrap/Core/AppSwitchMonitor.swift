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

    private let tabKeyCode = CGKeyCode(kVK_Tab)

    var onSwitchGestureDetected: (() -> Void)?

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
            FileHandle.standardError.write("Squirrel Trap DEBUG: gesture detected, firing callback\n".data(using: .utf8)!)
            let callback = onSwitchGestureDetected
            DispatchQueue.main.async {
                callback?()
            }

        case .flagsChanged:
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
