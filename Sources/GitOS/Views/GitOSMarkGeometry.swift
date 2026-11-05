import CoreGraphics
import Foundation

/// The GitOS mark: one repository's line forks towards several GitHub accounts, and the switch is
/// set to the one in use, like a railway junction. Shared by the app and `scripts/make-icon.swift`,
/// so it only needs CoreGraphics. Coordinates are y-down.
enum GitOSMarkGeometry {
    private static let lineWidth: CGFloat = 0.09
    private static let rootSize: CGFloat = 0.092
    private static let idleSize: CGFloat = 0.082
    private static let accountSize: CGFloat = 0.195
    private static let root = CGPoint(x: 0.13, y: 0.5)
    private static let fork = CGPoint(x: 0.27, y: 0.5)
    private static let account = CGPoint(x: 0.755, y: 0.5)
    private static let idleAccounts = [CGPoint(x: 0.68, y: 0.135), CGPoint(x: 0.68, y: 0.865)]

    private static func scaled(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private static func circle(_ center: CGPoint, _ radius: CGFloat, in rect: CGRect, stretchedBy stretch: CGFloat = 1) -> CGPath {
        let c = scaled(center, in: rect)
        let r = radius * rect.width
        return CGPath(ellipseIn: CGRect(x: c.x - r * stretch, y: c.y - r, width: r * stretch * 2, height: r * 2), transform: nil)
    }

    /// The accounts not in use, and the tracks that lead to them.
    static func idleTracks(in rect: CGRect) -> CGPath {
        var shape = CGMutablePath().copy()!
        for end in idleAccounts {
            let line = CGMutablePath()
            line.move(to: scaled(fork, in: rect))
            line.addCurve(to: scaled(end, in: rect),
                          control1: scaled(CGPoint(x: fork.x + 0.17, y: fork.y), in: rect),
                          control2: scaled(CGPoint(x: end.x - 0.24, y: end.y), in: rect))
            shape = shape.union(line.copy(strokingWithWidth: lineWidth * rect.width, lineCap: .round, lineJoin: .round, miterLimit: 10))
            shape = shape.union(circle(end, idleSize, in: rect))
        }
        return shape
    }

    /// The repository's line, running straight to the account in use.
    static func activeTrack(in rect: CGRect) -> CGPath {
        let line = CGMutablePath()
        line.move(to: scaled(root, in: rect))
        line.addLine(to: scaled(account, in: rect))
        return line.copy(strokingWithWidth: lineWidth * rect.width, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .union(circle(root, rootSize, in: rect))
    }

    /// The account in use: a disc with a person cut out of it.
    static func activeAccount(in rect: CGRect) -> CGPath {
        let head = circle(CGPoint(x: account.x, y: account.y - 0.058), 0.062, in: rect)
        let shoulders = circle(CGPoint(x: account.x, y: account.y + 0.135), 0.094, in: rect, stretchedBy: 1.25)
            .intersection(circle(account, accountSize - 0.04, in: rect))
        return circle(account, accountSize, in: rect).subtracting(head).subtracting(shoulders)
    }

    /// The whole mark as one shape, for one-color use. The track stops at the disc's edge, so the person stays cut out.
    static func solid(in rect: CGRect) -> CGPath {
        idleTracks(in: rect)
            .union(activeTrack(in: rect).subtracting(circle(account, accountSize, in: rect)))
            .union(activeAccount(in: rect))
    }

    /// The disc behind the person, so the track doesn't show through the cutout.
    static func activeAccountBacking(in rect: CGRect) -> CGPath {
        circle(account, accountSize, in: rect)
    }
}
