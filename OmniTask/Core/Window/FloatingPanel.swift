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

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
    }

    // MARK: - Mouse Events

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }

    // MARK: - Keyboard Events

    /// Prevent ESC from closing the panel
    override func cancelOperation(_ sender: Any?) {
        // Do nothing - consume ESC key to prevent panel from closing
    }
}
