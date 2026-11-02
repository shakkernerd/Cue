import CoreGraphics
import CueCore

enum Displays {
    /// The active displays' bounds, leaving out mirrors of another display.
    static func currentLayout() -> DisplayLayout {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return DisplayLayout(frames: []) }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return DisplayLayout(frames: []) }
        let frames = ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map(CGDisplayBounds)
        return DisplayLayout(frames: frames)
    }
}
