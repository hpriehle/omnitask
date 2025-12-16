import AppKit
import SwiftUI

/// Represents the fixed anchor point during panel expansion/collapse (9 positions)
enum ExpansionAnchor {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight

    /// Converts to SwiftUI UnitPoint for transition animations
    var unitPoint: UnitPoint {
        switch self {
        case .topLeft: return .topLeading
        case .top: return .top
        case .topRight: return .topTrailing
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .bottomLeft: return .bottomLeading
        case .bottom: return .bottom
        case .bottomRight: return .bottomTrailing
        }
    }
}

/// A floating NSPanel that stays on top across all Spaces and desktops
final class FloatingPanel: NSPanel {
    private let hostingView: NSHostingView<AnyView>

    init<Content: View>(contentView: Content) {
        self.hostingView = NSHostingView(rootView: AnyView(contentView))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        self.contentView = hostingView

        // Disable clipping to allow content (like toasts) to render outside bounds
        hostingView.layer?.masksToBounds = false
    }

    private func configurePanel() {
        // Floating behavior - stays on top
        isFloatingPanel = true
        level = .floating

        // Visible across all Spaces/Desktops (removed .transient to prevent auto-hide on focus loss)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Visual properties
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Interaction
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        // Don't become key window by default (non-activating)
        becomesKeyOnlyIfNeeded = true

        // Animation
        animationBehavior = .utilityWindow

        // Titlebar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        styleMask.remove(.titled)
    }

    /// Updates the SwiftUI content view
    func updateContent<Content: View>(_ content: Content) {
        hostingView.rootView = AnyView(content)
    }

    /// Resizes the panel with animation, anchored at the specified position
    func resize(to size: CGSize, anchor: ExpansionAnchor = .bottomRight, animated: Bool = true) {
        let currentFrame = frame
        var newOrigin: NSPoint

        // Calculate new origin based on anchor point
        // The anchor determines which point stays fixed during resize
        switch anchor {
        case .topLeft:
            // Top-left stays fixed, expand down-right
            newOrigin = NSPoint(
                x: currentFrame.minX,
                y: currentFrame.maxY - size.height
            )
        case .top:
            // Top-center stays fixed, expand down
            newOrigin = NSPoint(
                x: currentFrame.midX - size.width / 2,
                y: currentFrame.maxY - size.height
            )
        case .topRight:
            // Top-right stays fixed, expand down-left
            newOrigin = NSPoint(
                x: currentFrame.maxX - size.width,
                y: currentFrame.maxY - size.height
            )
        case .left:
            // Middle-left stays fixed, expand right
            newOrigin = NSPoint(
                x: currentFrame.minX,
                y: currentFrame.midY - size.height / 2
            )
        case .center:
            // Center stays fixed, expand outward
            newOrigin = NSPoint(
                x: currentFrame.midX - size.width / 2,
                y: currentFrame.midY - size.height / 2
            )
        case .right:
            // Middle-right stays fixed, expand left
            newOrigin = NSPoint(
                x: currentFrame.maxX - size.width,
                y: currentFrame.midY - size.height / 2
            )
        case .bottomLeft:
            // Bottom-left stays fixed, expand up-right
            newOrigin = NSPoint(
                x: currentFrame.minX,
                y: currentFrame.minY
            )
        case .bottom:
            // Bottom-center stays fixed, expand up
            newOrigin = NSPoint(
                x: currentFrame.midX - size.width / 2,
                y: currentFrame.minY
            )
        case .bottomRight:
            // Bottom-right stays fixed, expand up-left
            newOrigin = NSPoint(
                x: currentFrame.maxX - size.width,
                y: currentFrame.minY
            )
        }

        // Clamp to screen bounds to prevent going off-screen
        if let screenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let minX = screenFrame.minX
            let maxX = screenFrame.maxX - size.width
            newOrigin.x = max(minX, min(maxX, newOrigin.x))

            let minY = screenFrame.minY
            let maxY = screenFrame.maxY - size.height
            newOrigin.y = max(minY, min(maxY, newOrigin.y))
        }

        let newFrame = NSRect(origin: newOrigin, size: size)
        print("[FloatingPanel] Resizing from \(currentFrame) to \(newFrame) with anchor: \(anchor)")
        print("[FloatingPanel] Origin change: (\(currentFrame.origin.x), \(currentFrame.origin.y)) -> (\(newOrigin.x), \(newOrigin.y))")

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(newFrame, display: true)
            }, completionHandler: { [weak self] in
                print("[FloatingPanel] Animation complete, actual frame: \(self?.frame ?? .zero)")
            })
        } else {
            setFrame(newFrame, display: true)
            print("[FloatingPanel] Immediate resize complete, actual frame: \(frame)")
        }
    }

    // MARK: - Mouse Events

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }

    // MARK: - Window Activation

    /// Make window key and bring app to front when clicked
    /// This is needed for KeyboardShortcuts.Recorder to capture keystrokes
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        activateForKeyboardInput()
    }

    /// Explicitly activate and make key for keyboard input
    /// Temporarily removes nonactivatingPanel to allow proper keyboard focus
    func activateForKeyboardInput() {
        // Temporarily add .nonactivatingPanel to styleMask if removed, or ensure activation works
        // The key is to activate the app and make this window key
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)

        // Force the window to become first responder target
        if let contentView = contentView {
            makeFirstResponder(contentView)
        }
    }

    /// Enable full keyboard interaction mode (for shortcut recording)
    /// Call this when entering a view that needs keyboard input like KeyboardShortcuts.Recorder
    func enableKeyboardInputMode() {
        // Remove nonactivatingPanel to allow full keyboard interaction
        styleMask.remove(.nonactivatingPanel)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// Restore non-activating panel mode
    /// Call this when leaving keyboard-heavy views
    func disableKeyboardInputMode() {
        // Restore nonactivatingPanel behavior
        styleMask.insert(.nonactivatingPanel)
    }

    // MARK: - Keyboard Events

    /// Prevent ESC from closing the panel
    override func cancelOperation(_ sender: Any?) {
        // Do nothing - consume ESC key to prevent panel from closing
    }
}
