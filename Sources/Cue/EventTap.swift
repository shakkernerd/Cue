import CoreGraphics

/// A listen-only session event tap for pointer movement and modifier changes. Listen-only: events pass through
/// unchanged and undelayed, whatever the handlers do.
@MainActor
final class EventTap {
    private let onMove: @MainActor (CGEvent) -> Void
    private let onFlagsChanged: @MainActor (CGEvent) -> Void
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(onMove: @escaping @MainActor (CGEvent) -> Void, onFlagsChanged: @escaping @MainActor (CGEvent) -> Void) {
        self.onMove = onMove
        self.onFlagsChanged = onFlagsChanged
    }

    var isRunning: Bool { port != nil }

    /// Starts the tap on the main run loop. Returns false when macOS refuses it (no Accessibility permission).
    func start() -> Bool {
        if port != nil { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask,
            callback: eventTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        case .flagsChanged:
            onFlagsChanged(event)
        default:
            onMove(event)
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
        // The tap's run loop source is on the main run loop, so this runs on the main thread and the event stays there.
        nonisolated(unsafe) let event = event
        MainActor.assumeIsolated { tap.handle(type, event) }
    }
    return Unmanaged.passUnretained(event)
}
