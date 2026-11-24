import CoreGraphics

public enum Keystroke {
    /// Key-down and key-up events for `spec`, carrying exactly the spec's modifiers: modifiers the user is physically
    /// holding (such as the trigger's Control) are not added.
    public static func events(for spec: KeySpec) -> [CGEvent] {
        let source = CGEventSource(stateID: .privateState)
        return [true, false].compactMap { keyDown in
            let event = CGEvent(keyboardEventSource: source, virtualKey: spec.keyCode, keyDown: keyDown)
            event?.flags = spec.modifiers.eventFlags
            return event
        }
    }

    /// Posts `spec` at the HID level so global hotkey listeners see it, not only the frontmost app.
    /// Needs the Accessibility permission; without it macOS drops the events.
    public static func post(_ spec: KeySpec) {
        for event in events(for: spec) {
            event.post(tap: .cghidEventTap)
        }
    }
}
