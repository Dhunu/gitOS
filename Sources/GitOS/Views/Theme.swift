import SwiftUI

/// The active palette. Every color comes from here, and because this is observable, views
/// recolor as soon as the theme changes, without losing their state.
enum Theme {
    static var palette: ThemePalette { ThemeStore.shared.palette }

    static var accent: Color { palette.accent.color }
    static var head: Color { palette.head.color }

    // Surfaces
    static var canvas: Color { palette.canvas.color }
    static var panel: Color { palette.panel.color }
    static var field: Color { palette.field.color }

    // Status
    static var added: Color { palette.added.color }
    static var modified: Color { palette.modified.color }
    static var removed: Color { palette.removed.color }
    static var renamed: Color { palette.renamed.color }
    static var conflict: Color { palette.conflict.color }

    /// Commit graph lanes, and repository tiles.
    static var lanes: [Color] {
        [accent, renamed, modified, conflict, removed, added, palette.extraLane.color, palette.head.color]
    }

    /// A stable color for a name. `hashValue` changes on every launch, so this sums the scalars.
    static func lane(for name: String) -> Color {
        lanes[name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % lanes.count]
    }

    static var markGradient: LinearGradient {
        LinearGradient(colors: [palette.gradientStart.color, palette.gradientEnd.color],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
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

/// The GitOS mark at any size.
struct GitOSMark: View {
    var size: CGFloat = 20

    var body: some View {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        ZStack {
            Path(GitOSMarkGeometry.idleTracks(in: rect)).fill(Theme.accent.opacity(0.4))
            Path(GitOSMarkGeometry.activeTrack(in: rect).subtracting(GitOSMarkGeometry.activeAccountBacking(in: rect)))
                .fill(Theme.markGradient)
            Path(GitOSMarkGeometry.activeAccount(in: rect)).fill(Theme.head)
        }
        .frame(width: size, height: size)
    }

    /// One-color version for the menu bar.
    static var menuBarImage: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(GitOSMarkGeometry.solid(in: rect))
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
