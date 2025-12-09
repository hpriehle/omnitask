import SwiftUI
import KeyboardShortcuts

/// A button that opens a modal window for recording keyboard shortcuts.
/// Works around FloatingPanel's .nonactivatingPanel keyboard input issues.
/// Use this component instead of KeyboardShortcuts.Recorder directly when inside a non-activating panel.
struct ShortcutRecorderButton: View {
    let shortcutName: KeyboardShortcuts.Name
    let label: String

    @State private var recorderWindow: NSWindow?
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?

    init(shortcutName: KeyboardShortcuts.Name, label: String = "") {
        self.shortcutName = shortcutName
        self.label = label
        _currentShortcut = State(initialValue: KeyboardShortcuts.getShortcut(for: shortcutName))
    }

    var body: some View {
        HStack {
            if !label.isEmpty {
                Text(label)
            }

            Spacer()

            Button {
                openRecorderWindow()
            } label: {
                if let shortcut = currentShortcut {
                    Text(shortcut.description)
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text("Record Shortcut")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.bordered)
        }
        .onAppear {
            // Refresh shortcut on appear in case it changed
            currentShortcut = KeyboardShortcuts.getShortcut(for: shortcutName)
        }
    }

    private func openRecorderWindow() {
        let windowSize = CGSize(width: 300, height: 140)

        // Create a regular NSWindow (not NSPanel) so it can receive keyboard input
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Record Shortcut"
        window.isReleasedWhenClosed = false

        // Create content view with recorder
        let contentView = NSHostingView(rootView:
            ShortcutRecorderContent(
                shortcutName: shortcutName,
                onDone: { [weak window] in
                    window?.close()
                    // Update our local state after recording
                    currentShortcut = KeyboardShortcuts.getShortcut(for: shortcutName)
                }
            )
        )

        window.contentView = contentView

        // Position over the FloatingPanel instead of screen center
        if let panel = NSApp.windows.first(where: { $0 is FloatingPanel }) {
            let panelFrame = panel.frame
            let newOrigin = NSPoint(
                x: panelFrame.midX - windowSize.width / 2,
                y: panelFrame.midY - windowSize.height / 2
            )
            window.setFrameOrigin(newOrigin)
            // Set window level above the FloatingPanel
            window.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        } else {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        recorderWindow = window
    }
}

/// Content view for the shortcut recorder modal window
private struct ShortcutRecorderContent: View {
    let shortcutName: KeyboardShortcuts.Name
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Press your desired shortcut")
                .font(.headline)

            KeyboardShortcuts.Recorder("", name: shortcutName)
                .padding(.horizontal)

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding()
        .frame(width: 300, height: 140)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ShortcutRecorderButton(shortcutName: .toggleOmniTask, label: "Toggle OmniTask")
        ShortcutRecorderButton(shortcutName: .toggleOmniTask, label: "")
    }
    .padding()
    .frame(width: 300)
}
