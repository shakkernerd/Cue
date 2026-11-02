import CoreGraphics
import Dispatch
import Testing

@testable import CueCore

private let layout = DisplayLayout(frames: [CGRect(x: 0, y: 0, width: 2560, height: 1440)])
private let rightEdge = CGPoint(x: 2559, y: 700)
private let leftEdge = CGPoint(x: 0, y: 700)
private let inside = CGPoint(x: 2400, y: 700)
private let pushRight = CGVector(dx: 4, dy: 0)
private let pushLeft = CGVector(dx: -4, dy: 0)

private func keys(_ text: String) -> Action { .keys(try! KeySpec.parse(text)) }
private let usbc = Rule(trigger: Trigger(edge: .right, modifiers: .control), action: keys("ctrl+shift+1"))
private let hdmi = Rule(trigger: Trigger(edge: .left, modifiers: .control), action: keys("ctrl+shift+4"))

@Suite struct EdgeTriggerEngineTests {
    var engine = EdgeTriggerEngine(rules: [usbc, hdmi])

    mutating func move(_ point: CGPoint, _ delta: CGVector, _ modifiers: Modifiers = .control, at time: Double) {
        engine.pointerMoved(to: point, delta: delta, modifiers: modifiers, layout: layout, time: time)
    }

    mutating func deadline(_ point: CGPoint = rightEdge, _ modifiers: Modifiers = .control, at time: Double) -> Rule? {
        engine.deadlineReached(location: point, modifiers: modifiers, layout: layout, time: time)
    }

    @Test mutating func pushWithModifiersFiresAfterTheDwell() {
        move(inside, pushRight, at: 0.0)
        move(rightEdge, pushRight, at: 0.1)
        #expect(engine.pending?.rule == usbc)
        #expect(engine.pending?.deadline == 0.1 + 0.150)
        #expect(deadline(at: 0.249) == nil)
        #expect(engine.pending != nil, "an early call leaves the rule armed")
        #expect(deadline(at: 0.25) == usbc)
        #expect(engine.pending == nil)
    }

    @Test mutating func pointerPlacedOnTheEdgeWithoutMovementDoesNotArm() {
        // A warp or a programmatic move reports no delta.
        move(rightEdge, .zero, at: 0)
        #expect(engine.pending == nil)
    }

    @Test mutating func arrivalMovingAwayFromTheEdgeDoesNotArm() {
        // Logi Flow brings the pointer in at the left edge while the hand keeps moving right, Control still held.
        move(leftEdge, CGVector(dx: 6, dy: 1), at: 0)
        move(CGPoint(x: 0.5, y: 701), CGVector(dx: 3, dy: 0), at: 0.01)
        #expect(engine.pending == nil)
        // The user's own push into the left edge does arm.
        move(leftEdge, pushLeft, at: 0.02)
        #expect(engine.pending?.rule == hdmi)
    }

    @Test mutating func firesOncePerArrivalAndAgainAfterLeaving() {
        move(rightEdge, pushRight, at: 0)
        #expect(deadline(at: 0.15) == usbc)
        // Resting and pushing on: nothing more.
        move(rightEdge, pushRight, at: 0.2)
        move(CGPoint(x: 2559, y: 720), CGVector(dx: 2, dy: 20), at: 0.3)
        #expect(engine.pending == nil)
        #expect(deadline(at: 1.0) == nil)
        // Leave, come back: fires again.
        move(inside, pushLeft, at: 1.1)
        move(rightEdge, pushRight, at: 1.2)
        #expect(engine.pending?.rule == usbc)
        #expect(deadline(at: 1.35) == usbc)
    }

    @Test mutating func quickPassDoesNotFire() {
        move(rightEdge, pushRight, at: 0)
        move(inside, pushLeft, at: 0.1)
        #expect(engine.pending == nil)
        #expect(deadline(inside, at: 0.15) == nil)
    }

    @Test mutating func pointerGoneFromTheEdgeAtTheDeadlineDoesNotFire() {
        // Moved off the edge without an observed event (for example warped away).
        move(rightEdge, pushRight, at: 0)
        #expect(deadline(inside, at: 0.15) == nil)
        #expect(engine.pending == nil)
    }

    @Test mutating func modifiersMustMatchExactly() {
        move(rightEdge, pushRight, [.control, .option], at: 0)
        #expect(engine.pending == nil)
        move(rightEdge, pushRight, [], at: 0.1)
        #expect(engine.pending == nil)
        move(rightEdge, pushRight, .shift, at: 0.2)
        #expect(engine.pending == nil)
        // Releasing Option while still pushing makes it a Control push.
        move(rightEdge, pushRight, .control, at: 0.3)
        #expect(engine.pending?.rule == usbc)
    }

    @Test func capsLockAndFnAreIgnored() {
        let flags: CGEventFlags = [.maskControl, .maskAlphaShift, .maskSecondaryFn, .maskNumericPad, .maskNonCoalesced]
        #expect(Modifiers(flags: flags) == .control)
        #expect(Modifiers(flags: [.maskControl, .maskAlternate, .maskShift, .maskCommand]) == [.control, .option, .shift, .command])
        #expect(Modifiers(flags: .maskAlphaShift).isEmpty)
    }

    @Test mutating func modifierChangeDuringTheDwellCancels() {
        move(rightEdge, pushRight, at: 0)
        engine.modifiersChanged(to: [.control, .option])
        #expect(engine.pending == nil)
        #expect(deadline(at: 0.15) == nil)
        // Pressing back to Control alone does not re-arm: arming needs a push.
        engine.modifiersChanged(to: .control)
        #expect(engine.pending == nil)
    }

    @Test mutating func modifiersAtTheDeadlineMustStillMatch() {
        move(rightEdge, pushRight, at: 0)
        #expect(deadline(rightEdge, [], at: 0.15) == nil)
        #expect(deadline(rightEdge, [.control, .command], at: 0.15) == nil)
    }

    @Test mutating func edgeSharedWithAnotherDisplayNeverArms() {
        let twoDisplays = DisplayLayout(frames: [
            CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 2560, y: 0, width: 2560, height: 1440),
        ])
        engine.pointerMoved(to: rightEdge, delta: pushRight, modifiers: .control, layout: twoDisplays, time: 0)
        #expect(engine.pending == nil)
    }

    @Test mutating func noRulesNeverArm() {
        engine.setRules([])
        move(rightEdge, pushRight, at: 0)
        #expect(engine.pending == nil)
    }

    @Test mutating func ruleWithoutModifiersNeedsNoneHeld() {
        let bare = Rule(trigger: Trigger(edge: .bottom, modifiers: []), action: keys("f12"))
        engine.setRules([bare])
        move(CGPoint(x: 900, y: 1439), CGVector(dx: 0, dy: 3), .control, at: 0)
        #expect(engine.pending == nil)
        move(CGPoint(x: 900, y: 1439), CGVector(dx: 0, dy: 3), [], at: 0.1)
        #expect(engine.pending?.rule == bare)
    }
}

@MainActor
@Suite struct EdgeWatcherTimerTests {
    /// The dwell runs on a real timer: the rule fires with no further events after the push.
    @Test func firesAfterTheDwellWithoutFurtherEvents() async throws {
        var fired: [(rule: Rule, at: Double)] = []
        let watcher = EdgeWatcher(
            rules: [usbc],
            environment: EdgeWatcher.Environment(layout: { layout }, currentInput: { (rightEdge, .control) }),
            fire: { fired.append(($0, EdgeWatcher.uptime())) }
        )
        let start = EdgeWatcher.uptime()
        watcher.pointerMoved(to: rightEdge, delta: pushRight, modifiers: .control)
        try await Task.sleep(for: .milliseconds(100))
        // Only meaningful while the sleep did not overshoot toward the deadline (slow CI runners).
        if EdgeWatcher.uptime() - start < 0.140 { #expect(fired.isEmpty) }
        try await Task.sleep(for: .milliseconds(250))
        #expect(fired.count == 1)
        #expect(fired.first?.rule == usbc)
        if let at = fired.first?.at { #expect(at - start >= 0.150) }
        #expect(watcher.pending == nil)
    }

    @Test func leavingBeforeTheDwellCancelsTheTimer() async throws {
        final class Pointer { var location = rightEdge }
        let pointer = Pointer()
        var fired = 0
        // A long dwell, so a slow runner cannot reach the deadline before the pointer leaves.
        let watcher = EdgeWatcher(
            rules: [usbc], dwell: 1.0,
            environment: EdgeWatcher.Environment(layout: { layout }, currentInput: { (pointer.location, .control) }),
            fire: { _ in fired += 1 }
        )
        watcher.pointerMoved(to: rightEdge, delta: pushRight, modifiers: .control)
        try await Task.sleep(for: .milliseconds(50))
        pointer.location = inside
        watcher.pointerMoved(to: inside, delta: pushLeft, modifiers: .control)
        try await Task.sleep(for: .milliseconds(1200))
        #expect(fired == 0)
        #expect(watcher.pending == nil)
    }
}
