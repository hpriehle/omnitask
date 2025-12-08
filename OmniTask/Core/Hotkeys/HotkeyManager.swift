import Foundation
import KeyboardShortcuts

/// Manages global keyboard shortcuts for the app
final class HotkeyManager {
    static let shared = HotkeyManager()

    private init() {}

    func setupDefaultShortcuts() {
        // Set default toggle shortcut if not already set
        if KeyboardShortcuts.getShortcut(for: .toggleOmniTask) == nil {
            KeyboardShortcuts.setShortcut(.init(.t, modifiers: [.command, .shift]), for: .toggleOmniTask)
        }
    }

    func registerToggleHandler(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .toggleOmniTask, action: handler)
    }
}
