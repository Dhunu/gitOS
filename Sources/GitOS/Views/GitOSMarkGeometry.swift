import CoreGraphics
import Foundation

/// The GitOS mark: a "G" drawn as a commit graph. A branch runs around the ring and merges into
/// HEAD at the center. Shared by the app and `scripts/make-icon.swift`, so it only needs CoreGraphics.
/// Coordinates are y-down.
enum GitOSMarkGeometry {
    private static let radius: CGFloat = 0.36
    private static let lineWidth: CGFloat = 0.095
    private static let nodeSize: CGFloat = 0.085
    private static let startAngle: CGFloat = -48 * .pi / 180
    private static let bottomLeftAngle: CGFloat = -225 * .pi / 180
    private static let center = CGPoint(x: 0.5, y: 0.5)

    private static func scaled(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private static func onRing(_ angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private static func node(at point: CGPoint, in rect: CGRect) -> CGPath {
        let r = nodeSize * rect.width
        return CGPath(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2), transform: nil)
    }

    /// The ring and its commits, without the HEAD commit.
    static func graph(in rect: CGRect) -> CGPath {
        let line = CGMutablePath()
        line.addArc(center: scaled(center, in: rect), radius: radius * rect.width,
                    startAngle: startAngle, endAngle: -2 * .pi, clockwise: true)
        line.addLine(to: scaled(head, in: rect))
        var shape = line.copy(strokingWithWidth: lineWidth * rect.width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        for point in [onRing(startAngle), onRing(bottomLeftAngle)] {
            shape = shape.union(node(at: scaled(point, in: rect), in: rect))
        }
        return shape
    }

    /// The HEAD commit at the end of the "G"'s bar.
    static func headNode(in rect: CGRect) -> CGPath {
        node(at: scaled(head, in: rect), in: rect)
    }

    private static var head: CGPoint { CGPoint(x: center.x + 0.03, y: center.y) }
}
