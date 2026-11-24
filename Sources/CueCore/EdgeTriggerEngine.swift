import CoreGraphics

/// Decides when a rule fires. Pure state machine: callers feed it pointer observations, each with the modifiers held
/// at that event, and a monotonic time in seconds, and call `deadlineReached` when `pending.deadline` passes.
///
/// - A rule arms only when the pointer is on one of its display's outer edges, moving into that edge (a push), with
///   exactly the rule's modifiers held. A pointer placed or warped onto the edge has no push and does not arm.
/// - An armed rule fires when it is still on the edge with the same modifiers once `dwell` has passed.
/// - A pointer event off the edge or with other modifiers cancels it, and so does either condition at the deadline.
///   A modifier released and pressed again within the dwell, with no pointer event in between, is not seen.
/// - After firing, the edge stays spent until the pointer leaves it, so one arrival fires once.
public struct EdgeTriggerEngine: Sendable {
    public static let defaultDwell: Double = 0.150

    public struct Pending: Equatable, Sendable {
        public var rule: Rule
        public var deadline: Double
    }

    public let dwell: Double
    public private(set) var rules: [Rule]
    public private(set) var pending: Pending?
    /// Edges that fired and have not been left since.
    public private(set) var spent: Set<Edge> = []

    public init(rules: [Rule], dwell: Double = defaultDwell) {
        self.rules = rules
        self.dwell = dwell
    }

    public mutating func setRules(_ rules: [Rule]) {
        self.rules = rules
        pending = nil
    }

    /// A pointer movement to `location` by `delta`, with `modifiers` held.
    public mutating func pointerMoved(
        to location: CGPoint, delta: CGVector, modifiers: Modifiers, layout: DisplayLayout, time: Double
    ) {
        let edges = layout.outerEdges(at: location)
        spent.formIntersection(edges)
        if let pending, !(edges.contains(pending.rule.trigger.edge) && modifiers == pending.rule.trigger.modifiers) {
            self.pending = nil
        }
        guard pending == nil else { return }
        if let rule = rules.first(where: { rule in
            let edge = rule.trigger.edge
            return edges.contains(edge) && !spent.contains(edge) && modifiers == rule.trigger.modifiers
                && edge.isPushed(by: delta)
        }) {
            pending = Pending(rule: rule, deadline: time + dwell)
        }
    }

    /// Called at or after `pending.deadline` with the pointer's and keyboard's state at that moment.
    /// Returns the rule to fire, if the pointer still rests on the edge with the rule's modifiers.
    public mutating func deadlineReached(
        location: CGPoint, modifiers: Modifiers, layout: DisplayLayout, time: Double
    ) -> Rule? {
        guard let pending, time >= pending.deadline else { return nil }
        self.pending = nil
        let edges = layout.outerEdges(at: location)
        spent.formIntersection(edges)
        let edge = pending.rule.trigger.edge
        guard edges.contains(edge), modifiers == pending.rule.trigger.modifiers else { return nil }
        spent.insert(edge)
        return pending.rule
    }
}
