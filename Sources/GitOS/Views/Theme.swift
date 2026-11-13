import SwiftUI

/// The active palette. Every color comes from here, and because this is observable, views
/// recolor as soon as the theme changes, without losing their state.
enum Theme {
    static var palette: ThemePalette { ThemeStore.shared.palette }

    static var isFlat: Bool { ThemeStore.shared.style == .flat }
    /// Solid surfaces instead of the system's translucent ones: any custom theme, or the flat style.
    static var solid: Bool { palette.isCustom || isFlat }

    static var accent: Color { palette.accent.color }
    static var head: Color { palette.head.color }

    // Surfaces
    static var canvas: Color { palette.canvas.color }
    static var panel: Color { palette.panel.color }
    static var field: Color { palette.field.color }
    /// Flat style: hairline borders, and the fill and border of toolbar chips.
    static var line: Color { .primary.opacity(0.1) }
    static var chip: Color { .primary.opacity(0.05) }
    static var chipBorder: Color { .primary.opacity(0.12) }

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

extension View {
    /// Flat style: a toolbar control drawn as a solid rounded chip with a hairline border.
    func chip() -> some View {
        menuStyle(.button).buttonStyle(ChipButtonStyle())
    }
}

/// The flat style's buttons: solid fill, hairline border, 9pt corners, like the GitOS website.
struct ChipButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .padding(.horizontal, controlSize == .small || controlSize == .mini ? 8 : 12)
            .frame(height: Self.height(controlSize))
            .background(configuration.isPressed ? Theme.chipBorder : Theme.chip, in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.chipBorder) }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    static func height(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini: 18
        case .small: 22
        case .large, .extraLarge: 34
        default: 30
        }
    }
}

/// The flat style's main action: solid accent, 9pt corners, dark text.
struct FlatProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(Theme.canvas)
            .padding(.horizontal, 12)
            .frame(minHeight: ChipButtonStyle.height(controlSize))
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 9))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

extension View {
    /// `.bordered`, or the flat style's chip.
    @ViewBuilder func borderedButton() -> some View {
        if Theme.isFlat { buttonStyle(ChipButtonStyle()) } else { buttonStyle(.bordered) }
    }

    /// Sheets and popovers are glass panels on macOS 26; the flat style makes them solid.
    @ViewBuilder func flatPresentation() -> some View {
        if Theme.isFlat {
            scrollContentBackground(.hidden)
                .background(Theme.panel)
                .presentationBackground(Theme.panel)
        } else {
            self
        }
    }

    /// `.borderedProminent`, or the flat style's solid accent button.
    @ViewBuilder func prominentButton() -> some View {
        if Theme.isFlat { buttonStyle(FlatProminentButtonStyle()) } else { buttonStyle(.borderedProminent) }
    }
}

/// A segmented control: the system one in the glass style, solid chips in the flat style.
struct SegmentedControl<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        if Theme.isFlat {
            LabeledContent(title) {
                HStack(spacing: 2) {
                    ForEach(options.indices, id: \.self) { index in
                        let option = options[index]
                        let selected = option.value == selection
                        Button { selection = option.value } label: {
                            Text(option.label)
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, minHeight: 22)
                                .foregroundStyle(selected ? Theme.canvas : .primary)
                                .background(selected ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.chipBorder) }
                .fixedSize(horizontal: true, vertical: false)
            }
        } else {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { Text(options[$0].label).tag(options[$0].value) }
            }
            .pickerStyle(.segmented)
        }
    }
}

extension View {
    /// A sheet's Cancel and confirm buttons. The glass style puts them in the sheet's toolbar; the
    /// flat style draws them in its own bar, because the system's sheet toolbar can't be made solid.
    func sheetActions<Confirm: View>(cancel: @escaping () -> Void, @ViewBuilder confirm: () -> Confirm) -> some View {
        modifier(SheetActions(cancel: cancel, confirm: confirm()))
    }
}

private struct SheetActions<Confirm: View>: ViewModifier {
    let cancel: () -> Void
    let confirm: Confirm

    func body(content: Content) -> some View {
        if Theme.isFlat {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                    confirm.keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Theme.panel)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            // Every sheet using this sets its width; without this the bar's Spacer widens the sheet.
            .fixedSize(horizontal: true, vertical: false)
        } else {
            content.toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) { confirm }
            }
        }
    }
}
