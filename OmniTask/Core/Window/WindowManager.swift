import AppKit
import SwiftUI
import Combine

/// Represents the 9 snap positions on screen
enum SnapPosition: String, CaseIterable {
    case topLeft, topCenter, topRight
    case middleLeft, middleCenter, middleRight
    case bottomLeft, bottomCenter, bottomRight

    /// The expansion anchor for this snap position
    var expansionAnchor: ExpansionAnchor {
        switch self {
        case .topLeft: return .topLeft
        case .topCenter: return .top
        case .topRight: return .topRight
        case .middleLeft: return .left
        case .middleCenter: return .center
        case .middleRight: return .right
        case .bottomLeft: return .bottomLeft
        case .bottomCenter: return .bottom
        case .bottomRight: return .bottomRight
        }
    }
}

/// Manages the floating panel lifecycle, visibility, and position
@MainActor
final class WindowManager: ObservableObject {
    /// Shared instance for accessing from anywhere (set by AppDelegate)
    static var shared: WindowManager?

    private var panel: FloatingPanel?
    private var hideTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var isExpanded = false
    @Published private(set) var isVisible = false
    @Published private(set) var currentSnapPosition: SnapPosition = .bottomRight

    // Position preservation for expand/collapse
    private var collapsedOrigin: NSPoint?
    private var isCollapsingProgrammatically = false

    private let environment: AppEnvironment

    // Panel dimensions
    private var collapsedSize = CGSize(width: 100, height: 36)
    private let normalCollapsedSize = CGSize(width: 100, height: 36)
    private let currentTaskCollapsedSize = CGSize(width: 220, height: 36)
    private let expandedSize = CGSize(width: 360, height: 500)

    // Position persistence key
    private let snapPositionKey = "panelSnapPosition"

    init(environment: AppEnvironment) {
        print("[WindowManager] Initializing...")
        self.environment = environment

        // Restore saved snap position
        if let savedPositionRaw = UserDefaults.standard.string(forKey: snapPositionKey),
           let savedPosition = SnapPosition(rawValue: savedPositionRaw) {
            currentSnapPosition = savedPosition
            print("[WindowManager] Restored snap position: \(savedPosition)")
        }

        createPanel()
        print("[WindowManager] Initialization complete")
    }

    private func createPanel() {
        print("[WindowManager] Creating panel...")
        let contentView = MainPillView(
            isExpanded: Binding(
                get: { [weak self] in self?.isExpanded ?? false },
                set: { [weak self] in self?.setExpanded($0) }
            )
        )
        .environmentObject(environment)

        panel = FloatingPanel(contentView: contentView)
        print("[WindowManager] Panel created")

        // Position at current snap position
        if let screen = NSScreen.main {
            let position = snapPoint(for: currentSnapPosition, on: screen)
            panel?.setFrameOrigin(position)
            print("[WindowManager] Set initial position to \(currentSnapPosition): \(position)")
        }

        // Observe position changes to snap after drag
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.snapToNearestPosition()
            }
            .store(in: &cancellables)

        // Observe pill size changes (for current task width changes)
        NotificationCenter.default.publisher(for: .pillSizeChanged)
            .sink { [weak self] notification in
                if let size = notification.userInfo?["size"] as? CGSize {
                    self?.handlePillSizeChange(size)
                }
            }
            .store(in: &cancellables)
    }

    /// Handle dynamic pill size changes (e.g., when current task is set/cleared)
    private func handlePillSizeChange(_ newSize: CGSize) {
        guard !isExpanded else { return }

        let oldSize = collapsedSize
        collapsedSize = newSize

        // Only animate if size actually changed
        guard oldSize != newSize, let currentFrame = panel?.frame else { return }

        // Calculate new origin based on current snap position anchor
        let anchor = currentSnapPosition.expansionAnchor
        let newOrigin = calculateOrigin(for: newSize, from: currentFrame, anchor: anchor)

        print("[WindowManager] Pill size changed: \(oldSize) -> \(newSize)")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel?.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        }

        // Update stored collapsed origin
        collapsedOrigin = newOrigin
    }

    /// Calculate new origin to maintain anchor position during resize
    private func calculateOrigin(for newSize: CGSize, from currentFrame: NSRect, anchor: ExpansionAnchor) -> NSPoint {
        let oldSize = currentFrame.size
        let deltaW = newSize.width - oldSize.width
        let deltaH = newSize.height - oldSize.height

        var newOrigin = currentFrame.origin

        switch anchor {
        case .topLeft, .left, .bottomLeft:
            // Left anchors: origin x stays same
            break
        case .top, .center, .bottom:
            // Center anchors: shift x by half delta
            newOrigin.x -= deltaW / 2
        case .topRight, .right, .bottomRight:
            // Right anchors: shift x by full delta
            newOrigin.x -= deltaW
        }

        switch anchor {
        case .bottomLeft, .bottom, .bottomRight:
            // Bottom anchors: origin y stays same
            break
        case .left, .center, .right:
            // Center anchors: shift y by half delta
            newOrigin.y -= deltaH / 2
        case .topLeft, .top, .topRight:
            // Top anchors: shift y by full delta
            newOrigin.y -= deltaH
        }

        return newOrigin
    }

    /// Updates the SwiftUI content with the current isExpanded state
    private func updatePanelContent() {
        print("[WindowManager] updatePanelContent called, isExpanded: \(isExpanded)")
        print("[WindowManager] updatePanelContent: Frame BEFORE update: \(panel?.frame ?? .zero)")

        let contentView = MainPillView(
            isExpanded: Binding(
                get: { [weak self] in self?.isExpanded ?? false },
                set: { [weak self] in self?.setExpanded($0) }
            )
        )
        .environmentObject(environment)

        panel?.updateContent(contentView)
        print("[WindowManager] updatePanelContent: Frame AFTER update: \(panel?.frame ?? .zero)")
    }

    // MARK: - Snap Grid

    /// Calculates all 9 snap positions for a given screen
    private func snapPositions(for screen: NSScreen) -> [SnapPosition: NSPoint] {
        let frame = screen.visibleFrame
        let padding: CGFloat = 3
        let size = collapsedSize

        let left = frame.minX + padding
        let centerX = frame.midX - size.width / 2
        let right = frame.maxX - size.width - padding

        let bottom = frame.minY + padding
        let centerY = frame.midY - size.height / 2
        let top = frame.maxY - size.height - padding

        return [
            .topLeft: NSPoint(x: left, y: top),
            .topCenter: NSPoint(x: centerX, y: top),
            .topRight: NSPoint(x: right, y: top),
            .middleLeft: NSPoint(x: left, y: centerY),
            .middleCenter: NSPoint(x: centerX, y: centerY),
            .middleRight: NSPoint(x: right, y: centerY),
            .bottomLeft: NSPoint(x: left, y: bottom),
            .bottomCenter: NSPoint(x: centerX, y: bottom),
            .bottomRight: NSPoint(x: right, y: bottom),
        ]
    }

    /// Gets the snap point for a specific position on a screen
    private func snapPoint(for position: SnapPosition, on screen: NSScreen) -> NSPoint {
        snapPositions(for: screen)[position] ?? NSPoint(x: 100, y: 100)
    }

    /// Finds the nearest snap position to a given point
    private func nearestSnapPosition(to point: NSPoint, on screen: NSScreen) -> SnapPosition {
        let positions = snapPositions(for: screen)
        var nearest: SnapPosition = .bottomRight
        var minDistance: CGFloat = .infinity

        for (position, snapPoint) in positions {
            let distance = hypot(point.x - snapPoint.x, point.y - snapPoint.y)
            if distance < minDistance {
                minDistance = distance
                nearest = position
            }
        }
        return nearest
    }

    /// Snaps the panel to the nearest position after dragging
    private func snapToNearestPosition() {
        // Only snap when collapsed and not during programmatic collapse
        guard !isExpanded,
              !isCollapsingProgrammatically,
              let frame = panel?.frame,
              let screen = panel?.screen ?? NSScreen.main else { return }

        let position = nearestSnapPosition(to: frame.origin, on: screen)
        let snapPoint = self.snapPoint(for: position, on: screen)

        // Animate to snap position
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().setFrameOrigin(snapPoint)
        }

        currentSnapPosition = position
        saveSnapPosition()
        print("[WindowManager] Snapped to position: \(position)")
    }

    private func saveSnapPosition() {
        UserDefaults.standard.set(currentSnapPosition.rawValue, forKey: snapPositionKey)
    }

    // MARK: - Public API

    func showPanel() {
        print("[WindowManager] showPanel() called")
        hideTimer?.invalidate()
        hideTimer = nil

        panel?.orderFront(nil)
        isVisible = true
        print("[WindowManager] Panel is now visible")
    }

    func hidePanel(for duration: TimeInterval? = nil) {
        print("[WindowManager] hidePanel() called, duration: \(duration ?? -1)")
        panel?.orderOut(nil)
        isVisible = false
        isExpanded = false

        if let duration = duration {
            print("[WindowManager] Scheduling show timer for \(duration) seconds")
            hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    print("[WindowManager] Timer fired - showing panel")
                    self?.showPanel()
                }
            }
        }
        print("[WindowManager] Panel is now hidden")
    }

    func togglePanel() {
        print("[WindowManager] togglePanel() called, isVisible: \(isVisible)")
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func setExpanded(_ expanded: Bool) {
        print("[WindowManager] ========================================")
        print("[WindowManager] setExpanded(\(expanded)) called, current: \(isExpanded)")
        print("[WindowManager] Current panel frame: \(panel?.frame ?? .zero)")
        print("[WindowManager] Stored collapsedOrigin: \(collapsedOrigin ?? .zero)")

        guard expanded != isExpanded else {
            print("[WindowManager] Already in that state, skipping")
            return
        }

        let anchor = currentSnapPosition.expansionAnchor
        environment.expansionState.anchor = anchor
        print("[WindowManager] Using expansion anchor: \(anchor) from snap position: \(currentSnapPosition)")

        if expanded {
            // EXPANDING: Store current collapsed position first
            collapsedOrigin = panel?.frame.origin
            print("[WindowManager] EXPAND: Stored collapsed origin: \(collapsedOrigin ?? .zero)")
            print("[WindowManager] EXPAND: Current frame before expand: \(panel?.frame ?? .zero)")

            isExpanded = true
            // Resize FIRST before updatePanelContent() to prevent frame drift
            // (updatePanelContent swaps SwiftUI view which can auto-resize the frame)
            print("[WindowManager] EXPAND: Expanding panel to \(expandedSize)")
            panel?.resize(to: expandedSize, anchor: anchor, animated: true)
            updatePanelContent()
            panel?.makeKey()
            print("[WindowManager] EXPAND: Panel is now key window")
        } else {
            // COLLAPSING: Restore exact stored position (no recalculation = no drift)
            print("[WindowManager] COLLAPSE: Current frame: \(panel?.frame ?? .zero)")
            print("[WindowManager] COLLAPSE: Restoring to stored origin: \(collapsedOrigin ?? .zero)")

            isCollapsingProgrammatically = true

            // Restore exact stored origin instead of recalculating
            if let savedOrigin = collapsedOrigin {
                let newFrame = NSRect(origin: savedOrigin, size: collapsedSize)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.35
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel?.animator().setFrame(newFrame, display: true)
                }
            }

            // After animation completes (0.35s), swap to collapsed content
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self = self else { return }

                print("[WindowManager] COLLAPSE: Animation complete, swapping content")
                self.isExpanded = false
                self.updatePanelContent()

                // Force frame back to exact stored position after SwiftUI content swap
                // (updatePanelContent can trigger auto-resize that shifts the origin)
                if let savedOrigin = self.collapsedOrigin {
                    let correctFrame = NSRect(origin: savedOrigin, size: self.collapsedSize)
                    self.panel?.setFrame(correctFrame, display: true)
                    print("[WindowManager] COLLAPSE: Forced frame to: \(correctFrame)")
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isCollapsingProgrammatically = false
                    print("[WindowManager] COLLAPSE: Reset flag")
                }
            }
        }
        print("[WindowManager] ========================================")
    }

    func toggleExpanded() {
        print("[WindowManager] toggleExpanded() called")
        setExpanded(!isExpanded)
    }

    /// Moves the panel to a specific snap position
    func moveTo(position: SnapPosition) {
        guard let screen = panel?.screen ?? NSScreen.main else { return }
        let point = snapPoint(for: position, on: screen)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel?.animator().setFrameOrigin(point)
        }

        currentSnapPosition = position
        saveSnapPosition()
        print("[WindowManager] Moved to snap position: \(position)")
    }

    /// Resets the panel position to the default (bottom-right)
    func resetPosition() {
        print("[WindowManager] Resetting position to default (bottomRight)")
        moveTo(position: .bottomRight)
    }

    /// Gets the current panel frame
    var frame: NSRect? {
        panel?.frame
    }

    /// Get the center of the pill in screen coordinates (for confetti positioning)
    /// This uses the actual panel frame which is already in screen coordinates
    var pillCenterInScreenCoordinates: NSPoint? {
        guard let frame = panel?.frame else { return nil }
        return NSPoint(
            x: frame.midX,
            y: frame.midY
        )
    }

    /// Get center of COLLAPSED pill (works even when expanded/animating)
    /// Uses stored collapsed origin so confetti always appears at pill position
    var collapsedPillCenter: NSPoint {
        let origin = collapsedOrigin ?? panel?.frame.origin ?? .zero
        let center = NSPoint(
            x: origin.x + collapsedSize.width / 2,
            y: origin.y + collapsedSize.height / 2
        )
        print("[WindowManager] collapsedPillCenter - origin: \(origin), collapsedSize: \(collapsedSize), center: \(center)")
        return center
    }
}
