import CoreGraphics
import Testing

@testable import CueCore

@Suite struct EdgeGeometryTests {
    let single = DisplayLayout(frames: [CGRect(x: 0, y: 0, width: 2560, height: 1440)])

    @Test func singleDisplayEdgesAtThePointerLimits() {
        // The pointer stops at minX/minY and at maxX - 1 / maxY - 1.
        #expect(single.outerEdges(at: CGPoint(x: 0, y: 700)) == [.left])
        #expect(single.outerEdges(at: CGPoint(x: 2559, y: 700)) == [.right])
        #expect(single.outerEdges(at: CGPoint(x: 2559.5, y: 700)) == [.right])
        #expect(single.outerEdges(at: CGPoint(x: 1200, y: 0)) == [.top])
        #expect(single.outerEdges(at: CGPoint(x: 1200, y: 1439)) == [.bottom])
        #expect(single.outerEdges(at: CGPoint(x: 2559, y: 0)) == [.right, .top])
    }

    @Test func interiorAndOutsidePointsAreOnNoEdge() {
        #expect(single.outerEdges(at: CGPoint(x: 1, y: 700)).isEmpty)
        #expect(single.outerEdges(at: CGPoint(x: 2558, y: 700)).isEmpty)
        #expect(single.outerEdges(at: CGPoint(x: 2560, y: 700)).isEmpty)
        #expect(single.outerEdges(at: CGPoint(x: -1, y: 700)).isEmpty)
    }

    @Test func edgeSharedWithAnotherDisplayIsNotAnEdge() {
        let layout = DisplayLayout(frames: [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 2560, y: 0, width: 1920, height: 1440),
        ])
        #expect(layout.outerEdges(at: CGPoint(x: 2559, y: 700)).isEmpty)
        #expect(layout.outerEdges(at: CGPoint(x: 2560, y: 700)).isEmpty)
        #expect(layout.outerEdges(at: CGPoint(x: 0, y: 700)) == [.left])
        #expect(layout.outerEdges(at: CGPoint(x: 4479, y: 700)) == [.right])
    }

    @Test func onlyTheAdjoiningSegmentOfAPartlySharedEdgeIsExcluded() {
        // A smaller display to the right, aligned to the top: the right edge below it is still an edge.
        let layout = DisplayLayout(frames: [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 2560, y: 0, width: 1280, height: 800),
        ])
        #expect(layout.outerEdges(at: CGPoint(x: 2559, y: 400)).isEmpty)
        #expect(layout.outerEdges(at: CGPoint(x: 2559, y: 799)).isEmpty)
        #expect(layout.outerEdges(at: CGPoint(x: 2559, y: 800)) == [.right])
        #expect(layout.outerEdges(at: CGPoint(x: 2559, y: 1200)) == [.right])
        // The smaller display's own bottom edge is an outer edge.
        #expect(layout.outerEdges(at: CGPoint(x: 3000, y: 799)) == [.bottom])
    }

    @Test func stackedDisplaysShareTopAndBottom() {
        // Second display above the main one (negative y in global coordinates).
        let layout = DisplayLayout(frames: [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 320, y: -1080, width: 1920, height: 1080),
        ])
        #expect(layout.outerEdges(at: CGPoint(x: 1000, y: 0)).isEmpty)
        #expect(layout.outerEdges(at: CGPoint(x: 0, y: 0)) == [.left, .top])
        #expect(layout.outerEdges(at: CGPoint(x: 100, y: 0)) == [.top])
        #expect(layout.outerEdges(at: CGPoint(x: 2400, y: 0)) == [.top])
        #expect(layout.outerEdges(at: CGPoint(x: 1000, y: -1)).isEmpty)
        #expect(layout.outerEdges(at: CGPoint(x: 1000, y: -1080)) == [.top])
    }

    @Test func pushDirectionPerEdge() {
        #expect(Edge.left.isPushed(by: CGVector(dx: -3, dy: 0)))
        #expect(!Edge.left.isPushed(by: CGVector(dx: 3, dy: 0)))
        #expect(Edge.right.isPushed(by: CGVector(dx: 1, dy: 5)))
        #expect(!Edge.right.isPushed(by: CGVector(dx: 0, dy: 5)))
        #expect(Edge.top.isPushed(by: CGVector(dx: 0, dy: -1)))
        #expect(Edge.bottom.isPushed(by: CGVector(dx: 0, dy: 1)))
        #expect(!Edge.bottom.isPushed(by: .zero))
    }
}
