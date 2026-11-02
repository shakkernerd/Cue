import CoreGraphics

/// A side of a display.
public enum Edge: String, CaseIterable, Sendable {
    case left, right, top, bottom

    /// Whether a pointer movement of `delta` pushes toward this edge.
    /// Coordinates are global display coordinates: origin at the top left of the main display, y grows downward.
    public func isPushed(by delta: CGVector) -> Bool {
        switch self {
        case .left: delta.dx < 0
        case .right: delta.dx > 0
        case .top: delta.dy < 0
        case .bottom: delta.dy > 0
        }
    }
}

/// The active displays' frames in global display coordinates (the space of `CGDisplayBounds` and `CGEvent.location`).
public struct DisplayLayout: Equatable, Sendable {
    public var frames: [CGRect]

    public init(frames: [CGRect]) {
        self.frames = frames
    }

    /// How far inside a frame, in points, the pointer still counts as on its edge.
    /// The pointer stops at `maxX - 1` / `maxY - 1` on the right and bottom edges and at `minX` / `minY` on the others.
    static let band: CGFloat = 1

    /// The outer edges the point lies on: edges of the display that contains it, excluding any segment where another
    /// display adjoins, because there the pointer crosses to that display instead of resting on the edge.
    public func outerEdges(at point: CGPoint) -> Set<Edge> {
        guard let index = frames.firstIndex(where: { $0.contains(point) }) else { return [] }
        let frame = frames[index]
        var edges = Set<Edge>()
        if point.x < frame.minX + Self.band { edges.insert(.left) }
        if point.x >= frame.maxX - Self.band { edges.insert(.right) }
        if point.y < frame.minY + Self.band { edges.insert(.top) }
        if point.y >= frame.maxY - Self.band { edges.insert(.bottom) }
        guard !edges.isEmpty else { return [] }

        for (otherIndex, other) in frames.enumerated() where otherIndex != index {
            for edge in edges where Self.adjoins(other, frame, along: edge, at: point) {
                edges.remove(edge)
            }
        }
        return edges
    }

    /// Whether `other` touches `frame`'s `edge` at the point's position along that edge.
    private static func adjoins(_ other: CGRect, _ frame: CGRect, along edge: Edge, at point: CGPoint) -> Bool {
        let tolerance = band
        switch edge {
        case .left:
            return abs(other.maxX - frame.minX) < tolerance && point.y >= other.minY && point.y < other.maxY
        case .right:
            return abs(other.minX - frame.maxX) < tolerance && point.y >= other.minY && point.y < other.maxY
        case .top:
            return abs(other.maxY - frame.minY) < tolerance && point.x >= other.minX && point.x < other.maxX
        case .bottom:
            return abs(other.minY - frame.maxY) < tolerance && point.x >= other.minX && point.x < other.maxX
        }
    }
}
