import CoreGraphics

/// The GitOS "Points" mark: a rail switch whose route is set to one account (the dot), while the
/// other blade stands open. Drawn in the brand's 1024-unit design space (see Resources/Brand) and
/// fitted into any rect. Coordinates are y-down.
enum GitOSMarkGeometry {
    /// The mark's bounds in design units.
    static let box = CGRect(x: 312, y: 184, width: 444, height: 664)
    /// The one stroke weight, in design units.
    private static let weight: CGFloat = 96

    /// Maps design units into `rect`, aspect-fit and centred.
    static func transform(in rect: CGRect) -> CGAffineTransform {
        let k = min(rect.width / box.width, rect.height / box.height)
        return CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: k, y: k)
            .translatedBy(x: -box.midX, y: -box.midY)
    }

    private static func fitted(_ path: CGPath, in rect: CGRect) -> CGPath {
        var t = transform(in: rect)
        return path.copy(using: &t) ?? path
    }

    private static func stroked(_ path: CGPath) -> CGPath {
        path.copy(strokingWithWidth: weight, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    /// The set route: the stem and the arm that runs to the account in use.
    static func route(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 512, y: 800))
        p.addLine(to: CGPoint(x: 512, y: 620))
        p.addCurve(to: CGPoint(x: 664, y: 300), control1: CGPoint(x: 512, y: 470), control2: CGPoint(x: 664, y: 450))
        return fitted(stroked(p), in: rect)
    }

    /// The open blade: the other account's arm, stopping short of the route.
    static func openBlade(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 431.44, y: 454.90))
        p.addCurve(to: CGPoint(x: 360, y: 300), control1: CGPoint(x: 395.02, y: 414.05), control2: CGPoint(x: 360, y: 372))
        return fitted(stroked(p), in: rect)
    }

    /// The account in use.
    static func node(in rect: CGRect) -> CGPath {
        fitted(CGPath(ellipseIn: CGRect(x: 664 - 92, y: 276 - 92, width: 184, height: 184), transform: nil), in: rect)
    }

    /// The whole mark as one shape, for one-color use such as the menu bar.
    static func solid(in rect: CGRect) -> CGPath {
        route(in: rect).union(openBlade(in: rect)).union(node(in: rect))
    }
}
