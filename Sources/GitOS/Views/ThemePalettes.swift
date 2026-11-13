import Observation
import SwiftUI

/// A color for light and dark appearance. Themes with one appearance use the same value twice.
struct ThemeColor: Sendable, Hashable {
    let light: UInt32
    let dark: UInt32

    init(_ hex: UInt32) {
        light = hex
        dark = hex
    }

    init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    var color: Color { Color(light: light, dark: dark) }
}

/// One selectable theme. Colors follow what each VS Code theme uses for the same job:
/// `canvas` is the editor, `panel` the side bar, `field` the input boxes.
struct ThemePalette: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    /// Forced appearance. Nil follows the system.
    var scheme: ColorSchemeChoice?
    let accent, head: ThemeColor
    let canvas, panel, field: ThemeColor
    let added, modified, removed, renamed, conflict: ThemeColor
    let extraLane: ThemeColor
    let gradientStart, gradientEnd: ThemeColor

    enum ColorSchemeChoice: Sendable {
        case light, dark

        var colorScheme: ColorScheme { self == .light ? .light : .dark }
    }

    /// The default keeps the system's translucent sidebar and window.
    var isCustom: Bool { id != Self.gitOS.id }

    static func named(_ id: String) -> ThemePalette {
        all.first { $0.id == id } ?? gitOS
    }

    private static func make(
        _ id: String, _ name: String, _ scheme: ColorSchemeChoice,
        accent: UInt32, head: UInt32, canvas: UInt32, panel: UInt32, field: UInt32,
        added: UInt32, modified: UInt32, removed: UInt32, renamed: UInt32, conflict: UInt32, extra: UInt32
    ) -> ThemePalette {
        ThemePalette(
            id: id, name: name, scheme: scheme,
            accent: .init(accent), head: .init(head),
            canvas: .init(canvas), panel: .init(panel), field: .init(field),
            added: .init(added), modified: .init(modified), removed: .init(removed),
            renamed: .init(renamed), conflict: .init(conflict), extraLane: .init(extra),
            gradientStart: .init(accent), gradientEnd: .init(renamed)
        )
    }

    /// GitOS's own palette, taken from the app icon. Adapts to light and dark mode.
    static let gitOS = ThemePalette(
        id: "gitos", name: "GitOS", scheme: nil,
        accent: .init(light: 0x0F857B, dark: 0x2BA799), head: .init(light: 0xB9791F, dark: 0xFFC978),
        canvas: .init(light: 0xF7F8FA, dark: 0x14171F), panel: .init(light: 0xEFF2F4, dark: 0x1A1E28),
        field: .init(light: 0xFFFFFF, dark: 0x10131A),
        added: .init(light: 0x2F8A5F, dark: 0x6CC79A), modified: .init(light: 0xAD7419, dark: 0xE3B66B),
        removed: .init(light: 0xBF4E5A, dark: 0xEA8F95), renamed: .init(light: 0x4E69C9, dark: 0x93A8F2),
        conflict: .init(light: 0x8256C4, dark: 0xB89AEE), extraLane: .init(light: 0x2F86B3, dark: 0x7CC0E6),
        gradientStart: .init(light: 0x13A08F, dark: 0x6FE9D3), gradientEnd: .init(light: 0x5470DE, dark: 0x8FA4FF)
    )

    static let all: [ThemePalette] = [
        gitOS,
        make("dark-plus", "Dark+", .dark,
             accent: 0x3794FF, head: 0xDCDCAA, canvas: 0x1E1E1E, panel: 0x252526, field: 0x3C3C3C,
             added: 0x81B88B, modified: 0xE2C08D, removed: 0xF48771, renamed: 0x75BEFF, conflict: 0xC586C0, extra: 0x4EC9B0),
        make("monokai", "Monokai", .dark,
             accent: 0xA6E22E, head: 0xFD971F, canvas: 0x272822, panel: 0x1E1F1C, field: 0x35362E,
             added: 0xA6E22E, modified: 0xE6DB74, removed: 0xF92672, renamed: 0x66D9EF, conflict: 0xAE81FF, extra: 0xFD971F),
        make("tokyo-night", "Tokyo Night", .dark,
             accent: 0x7AA2F7, head: 0xFF9E64, canvas: 0x1A1B26, panel: 0x16161E, field: 0x14141B,
             added: 0x9ECE6A, modified: 0xE0AF68, removed: 0xF7768E, renamed: 0x7DCFFF, conflict: 0xBB9AF7, extra: 0x73DACA),
        make("dracula", "Dracula", .dark,
             accent: 0xBD93F9, head: 0xFFB86C, canvas: 0x282A36, panel: 0x21222C, field: 0x191A21,
             added: 0x50FA7B, modified: 0xF1FA8C, removed: 0xFF5555, renamed: 0x8BE9FD, conflict: 0xFF79C6, extra: 0xFFB86C),
        make("one-dark-pro", "One Dark Pro", .dark,
             accent: 0x61AFEF, head: 0xD19A66, canvas: 0x282C34, panel: 0x21252B, field: 0x1D1F23,
             added: 0x98C379, modified: 0xE5C07B, removed: 0xE06C75, renamed: 0x56B6C2, conflict: 0xC678DD, extra: 0xD19A66),
        make("github-dark", "GitHub Dark", .dark,
             accent: 0x58A6FF, head: 0xD29922, canvas: 0x0D1117, panel: 0x161B22, field: 0x010409,
             added: 0x3FB950, modified: 0xD29922, removed: 0xF85149, renamed: 0x79C0FF, conflict: 0xBC8CFF, extra: 0x39C5CF),
        make("github-light", "GitHub Light", .light,
             accent: 0x0969DA, head: 0x9A6700, canvas: 0xFFFFFF, panel: 0xF6F8FA, field: 0xFFFFFF,
             added: 0x1A7F37, modified: 0x9A6700, removed: 0xCF222E, renamed: 0x0969DA, conflict: 0x8250DF, extra: 0x1B7C83),
        make("nord", "Nord", .dark,
             accent: 0x88C0D0, head: 0xD08770, canvas: 0x2E3440, panel: 0x272C36, field: 0x3B4252,
             added: 0xA3BE8C, modified: 0xEBCB8B, removed: 0xE5949C, renamed: 0x81A1C1, conflict: 0xB48EAD, extra: 0x8FBCBB),
        make("catppuccin-mocha", "Catppuccin Mocha", .dark,
             accent: 0xCBA6F7, head: 0xFAB387, canvas: 0x1E1E2E, panel: 0x181825, field: 0x11111B,
             added: 0xA6E3A1, modified: 0xF9E2AF, removed: 0xF38BA8, renamed: 0x89B4FA, conflict: 0xF5C2E7, extra: 0x94E2D5),
        make("night-owl", "Night Owl", .dark,
             accent: 0x82AAFF, head: 0xF78C6C, canvas: 0x011627, panel: 0x01111D, field: 0x0B253A,
             added: 0xADDB67, modified: 0xECC48D, removed: 0xEF5350, renamed: 0x7FDBCA, conflict: 0xC792EA, extra: 0x21C7A8),
        make("gruvbox-dark", "Gruvbox Dark", .dark,
             accent: 0xFE8019, head: 0xFABD2F, canvas: 0x282828, panel: 0x1D2021, field: 0x3C3836,
             added: 0xB8BB26, modified: 0xFABD2F, removed: 0xFB4934, renamed: 0x83A598, conflict: 0xD3869B, extra: 0x8EC07C),
        make("rose-pine", "Rosé Pine", .dark,
             accent: 0xC4A7E7, head: 0xF6C177, canvas: 0x191724, panel: 0x1F1D2E, field: 0x26233A,
             added: 0x9CCFD8, modified: 0xF6C177, removed: 0xEB6F92, renamed: 0x7FB6C9, conflict: 0xEBBCBA, extra: 0xC4A7E7),
        make("solarized-dark", "Solarized Dark", .dark,
             accent: 0x2AA198, head: 0xCB8A0C, canvas: 0x002B36, panel: 0x00212B, field: 0x073642,
             added: 0x93A516, modified: 0xCB8A0C, removed: 0xE8554F, renamed: 0x4BA3E3, conflict: 0xE0559A, extra: 0x8A8FE0),
        make("solarized-light", "Solarized Light", .light,
             accent: 0x1B7A72, head: 0x8C6A00, canvas: 0xFDF6E3, panel: 0xEEE8D5, field: 0xFFFBEF,
             added: 0x657500, modified: 0x8C6A00, removed: 0xC6281F, renamed: 0x1E6FB0, conflict: 0xB42A6E, extra: 0x5459AE),
    ]
}

/// Holds the active palette. Observable, so `Theme`'s colors track it.
@Observable
final class ThemeStore: @unchecked Sendable {
    static let shared = ThemeStore()
    var palette = ThemePalette.gitOS
    var style = WindowStyle.glass

    func apply(_ preferences: Preferences) {
        palette = .named(preferences.themeID)
        style = preferences.windowStyle
    }
}

/// How the window is drawn: macOS's translucent Liquid Glass, or solid panels with hairline
/// borders, as on the GitOS website.
enum WindowStyle: String, Codable, CaseIterable, Sendable {
    case glass, flat

    var title: String { self == .glass ? "Glass" : "Flat" }
}

extension View {
    /// Applies the active theme to a window: its appearance, accent and background.
    func themedWindow() -> some View {
        modifier(ThemedWindow())
    }
}

private struct ThemedWindow: ViewModifier {
    func body(content: Content) -> some View {
        let palette = Theme.palette
        content
            .tint(Theme.accent)
            .preferredColorScheme(palette.scheme?.colorScheme)
            .containerBackground(Theme.solid ? AnyShapeStyle(Theme.panel) : AnyShapeStyle(.windowBackground),
                                 for: .window)
            .modifier(FlatControls())
    }
}

/// The flat style replaces macOS 26's glass buttons and menu buttons everywhere at once: views that
/// don't pick a style themselves inherit these, sheets included. Explicit `.borderless` and `.plain` stay.
private struct FlatControls: ViewModifier {
    func body(content: Content) -> some View {
        if Theme.isFlat {
            content
                .buttonStyle(ChipButtonStyle())
                .menuStyle(.button)
                // Forms and lists show the solid panel behind them instead of the system's grey.
                .scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

/// A grid of theme cards in Settings, each drawn in that theme's own colors.
struct ThemePicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 10)], spacing: 10) {
            ForEach(ThemePalette.all) { palette in
                Button { selection = palette.id } label: {
                    ThemeCard(palette: palette, isSelected: palette.id == selection)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(palette.name)
                .accessibilityAddTraits(palette.id == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ThemeCard: View {
    let palette: ThemePalette
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                palette.panel.color.frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(palette.accent.color).frame(width: 44, height: 5)
                    RoundedRectangle(cornerRadius: 2).fill(palette.added.color).frame(width: 60, height: 5)
                    RoundedRectangle(cornerRadius: 2).fill(palette.removed.color).frame(width: 34, height: 5)
                    RoundedRectangle(cornerRadius: 2).fill(palette.modified.color).frame(width: 50, height: 5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .background(palette.canvas.color)
            }
            .frame(height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.separator),
                                  lineWidth: isSelected ? 2 : 1)
            }
            HStack(spacing: 4) {
                Text(palette.name).font(.caption).lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
