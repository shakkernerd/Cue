import CoreGraphics
import Dispatch

/// Runs `EdgeTriggerEngine` against live input: schedules a main-queue timer for each armed rule, so a rule fires
/// after its dwell even when no further events arrive, and checks the real pointer and modifier state at that moment.
@MainActor
public final class EdgeWatcher {
    /// What the watcher reads from the system. Injected so tests can drive it.
    public struct Environment {
        public var layout: @MainActor () -> DisplayLayout
        /// The pointer location and held modifiers right now.
        public var currentInput: @MainActor () -> (location: CGPoint, modifiers: Modifiers)
        /// Monotonic seconds on the same clock as `DispatchTime`.
        public var now: @MainActor () -> Double

        public init(
            layout: @escaping @MainActor () -> DisplayLayout,
            currentInput: @escaping @MainActor () -> (location: CGPoint, modifiers: Modifiers),
            now: @escaping @MainActor () -> Double = EdgeWatcher.uptime
        ) {
            self.layout = layout
            self.currentInput = currentInput
            self.now = now
        }
    }

    public nonisolated static func uptime() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private var engine: EdgeTriggerEngine
    private let environment: Environment
    private let fire: @MainActor (Rule) -> Void
    private var timer: DispatchWorkItem?
    private var scheduledDeadline: Double?

    public init(
        rules: [Rule], dwell: Double = EdgeTriggerEngine.defaultDwell, environment: Environment,
        fire: @escaping @MainActor (Rule) -> Void
    ) {
        engine = EdgeTriggerEngine(rules: rules, dwell: dwell)
        self.environment = environment
        self.fire = fire
    }

    public var pending: EdgeTriggerEngine.Pending? { engine.pending }

    public func setRules(_ rules: [Rule]) {
        engine.setRules(rules)
        schedule()
    }

    public func pointerMoved(to location: CGPoint, delta: CGVector, modifiers: Modifiers) {
        engine.pointerMoved(
            to: location, delta: delta, modifiers: modifiers, layout: environment.layout(), time: environment.now())
        schedule()
    }

    /// Keeps exactly one timer, for the engine's current deadline.
    private func schedule() {
        let deadline = engine.pending?.deadline
        guard deadline != scheduledDeadline else { return }
        timer?.cancel()
        timer = nil
        scheduledDeadline = deadline
        guard let deadline else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.deadlinePassed() }
        }
        timer = item
        let delay = max(0, deadline - environment.now())
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func deadlinePassed() {
        timer = nil
        scheduledDeadline = nil
        let input = environment.currentInput()
        if let rule = engine.deadlineReached(
            location: input.location, modifiers: input.modifiers, layout: environment.layout(), time: environment.now())
        {
            fire(rule)
        }
        // Still pending only if the timer ran early; schedule it again.
        schedule()
    }
}
