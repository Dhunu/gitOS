import SwiftUI

extension EnvironmentValues {
    /// Whether the repo window is in focus mode: the detail pane of the current screen takes the
    /// whole window and the chrome around it (sidebar, list, tab bar, status bar) gets out of the way.
    @Entry var focusMode: Binding<Bool> = .constant(false)
}

extension FocusedValues {
    /// Exposes the key window's focus mode to the menu bar (View › Enter Focus Mode).
    @Entry var focusMode: Binding<Bool>?
}

/// Expands the surrounding detail pane to the whole window, or brings the chrome back.
/// Sits in the header of every detail pane that can get crowded.
struct FocusModeButton: View {
    @Environment(\.focusMode) private var focusMode

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { focusMode.wrappedValue.toggle() }
        } label: {
            Image(systemName: focusMode.wrappedValue
                  ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.borderless)
        .help(focusMode.wrappedValue ? "Exit focus mode (⇧⌘F or Esc)"
              : "Focus: expand this pane to the whole window (⇧⌘F)")
    }
}

/// View › Enter/Exit Focus Mode (⇧⌘F) for the key window.
struct FocusModeCommands: Commands {
    @FocusedBinding(\.focusMode) private var focusMode: Bool?

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button(focusMode == true ? "Exit Focus Mode" : "Enter Focus Mode") {
                withAnimation(.snappy(duration: 0.2)) { focusMode?.toggle() }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(focusMode == nil)
        }
    }
}
