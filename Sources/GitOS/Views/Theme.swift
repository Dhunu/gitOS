import SwiftUI

/// GitOS's palette, taken from the app icon: ink backgrounds, a teal accent and muted status colors.
/// Every color adapts to light and dark mode.
enum Theme {
    static let accent = Color(light: 0x0F857B, dark: 0x2BA799)
    static let head = Color(light: 0xB9791F, dark: 0xFFC978)

    // Surfaces
    static let canvas = Color(light: 0xF7F8FA, dark: 0x14171F)
    static let panel = Color(light: 0xEFF2F4, dark: 0x1A1E28)
    static let field = Color(light: 0xFFFFFF, dark: 0x10131A)

    // Status
    static let added = Color(light: 0x2F8A5F, dark: 0x6CC79A)
    static let modified = Color(light: 0xAD7419, dark: 0xE3B66B)
    static let removed = Color(light: 0xBF4E5A, dark: 0xEA8F95)
    static let renamed = Color(light: 0x4E69C9, dark: 0x93A8F2)
    static let conflict = Color(light: 0x8256C4, dark: 0xB89AEE)

    /// Commit graph lanes, and repository tiles.
    static let lanes: [Color] = [
        accent, renamed, modified, conflict, removed, added,
        Color(light: 0x2F86B3, dark: 0x7CC0E6), Color(light: 0xA8634A, dark: 0xDDA188),
    ]

    /// A stable color for a name. `hashValue` changes on every launch, so this sums the scalars.
    static func lane(for name: String) -> Color {
        lanes[name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % lanes.count]
    }

    static let markGradient = LinearGradient(
        colors: [Color(light: 0x13A08F, dark: 0x6FE9D3), Color(light: 0x5470DE, dark: 0x8FA4FF)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// The GitOS "G" at any size.
struct GitOSMark: View {
    var size: CGFloat = 20

    var body: some View {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        ZStack {
            Path(GitOSMarkGeometry.graph(in: rect)).fill(Theme.markGradient)
            Path(GitOSMarkGeometry.headNode(in: rect)).fill(Theme.head)
        }
        .frame(width: size, height: size)
    }

    /// One-color version for the menu bar.
    static var menuBarImage: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(GitOSMarkGeometry.graph(in: rect))
            context.addPath(GitOSMarkGeometry.headNode(in: rect))
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// An empty state with the mark, for the places where GitOS greets you.
struct GitOSWelcome<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            GitOSMark(size: 64)
            VStack(spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text(message).foregroundStyle(.secondary)
            }
            actions.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A small colored label, used for refs and file states.
struct Pill: View {
    let text: String
    var tint: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium).monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(tint.opacity(0.14), in: Capsule())
            .lineLimit(1)
    }
}

extension View {
    /// A list that sits on the GitOS canvas instead of the default window background.
    func canvasList() -> some View {
        scrollContentBackground(.hidden).background(Theme.canvas)
    }
}
