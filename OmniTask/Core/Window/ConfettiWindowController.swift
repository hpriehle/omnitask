import AppKit
import SwiftUI

/// Notification to trigger confetti at a specific screen position
extension Notification.Name {
    static let triggerConfetti = Notification.Name("triggerConfetti")
}

/// Manages a transparent window that displays confetti on top of all other windows
@MainActor
final class ConfettiWindowController {
    private var window: NSWindow?

    static let shared = ConfettiWindowController()

    private init() {
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: .triggerConfetti,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("[ConfettiWindowController] Received triggerConfetti notification")
            Task { @MainActor in
                // Get position from notification userInfo (captured synchronously at trigger time)
                guard let position = notification.userInfo?["position"] as? NSPoint else {
                    print("[ConfettiWindowController] ERROR: No position in notification userInfo")
                    return
                }
                print("[ConfettiWindowController] Position from notification: \(position)")
                self?.showConfetti(at: position)
            }
        }
    }

    /// Show confetti burst at a specific screen position
    func showConfetti(at position: NSPoint) {
        print("[ConfettiWindowController] showConfetti called at position: \(position)")

        // Create the confetti window if needed
        let confettiWindow = createConfettiWindow()
        print("[ConfettiWindowController] Created confetti window")

        // Size of the confetti area (particles expand within this)
        let windowSize = CGSize(width: 300, height: 300)

        // Center the window on the position (confetti expands from center)
        let windowOrigin = NSPoint(
            x: position.x - windowSize.width / 2,
            y: position.y - windowSize.height / 2
        )
        print("[ConfettiWindowController] Window origin: \(windowOrigin), size: \(windowSize)")

        confettiWindow.setFrame(
            NSRect(origin: windowOrigin, size: windowSize),
            display: true
        )

        // Show the window
        confettiWindow.orderFront(nil)
        window = confettiWindow
        print("[ConfettiWindowController] Window displayed, level: \(confettiWindow.level.rawValue)")

        // Create and set the confetti view
        let confettiView = DesktopConfettiView {
            // Cleanup when animation completes
            print("[ConfettiWindowController] Confetti animation complete, cleaning up")
            Task { @MainActor [weak self] in
                self?.window?.orderOut(nil)
                self?.window = nil
            }
        }

        let hostingView = NSHostingView(rootView: confettiView)
        confettiWindow.contentView = hostingView
        print("[ConfettiWindowController] Confetti view attached to window")
    }

    private func createConfettiWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Highest window level - above everything
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))

        // Transparent background
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false

        // Don't capture mouse events - click through
        window.ignoresMouseEvents = true

        // Visible on all spaces
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        return window
    }
}

/// SwiftUI view for desktop confetti (larger, more spread out)
private struct DesktopConfettiView: View {
    let onComplete: () -> Void

    @State private var particles: [DesktopConfettiParticle] = []
    @State private var hasTriggered = false

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                particle.shape
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size * particle.aspectRatio)
                    .rotationEffect(.degrees(particle.rotation))
                    .offset(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
                    .scaleEffect(particle.scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !hasTriggered {
                hasTriggered = true
                triggerConfetti()
            }
        }
    }

    private func triggerConfetti() {
        let particleCount = 40
        let duration: TimeInterval = 1.5

        // Generate particles with varied properties
        particles = (0..<particleCount).map { _ in
            // Random angle for explosion direction
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 80...150)

            return DesktopConfettiParticle(
                id: UUID(),
                color: confettiColors.randomElement() ?? .yellow,
                size: CGFloat.random(in: 6...12),
                aspectRatio: CGFloat.random(in: 0.6...1.4),
                x: 0,
                y: 0,
                targetX: cos(angle) * distance,
                targetY: sin(angle) * distance,
                opacity: 1.0,
                scale: CGFloat.random(in: 0.8...1.2),
                rotation: Double.random(in: 0...360),
                targetRotation: Double.random(in: -180...180),
                shape: [AnyShape(Circle()), AnyShape(Rectangle()), AnyShape(RoundedRectangle(cornerRadius: 2))].randomElement()!
            )
        }

        // Animate particles outward with rotation
        withAnimation(.easeOut(duration: duration * 0.5)) {
            for i in particles.indices {
                particles[i].x = particles[i].targetX
                particles[i].y = particles[i].targetY
                particles[i].rotation += particles[i].targetRotation
            }
        }

        // Fade out, fall, and shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.3) {
            withAnimation(.easeIn(duration: duration * 0.7)) {
                for i in particles.indices {
                    particles[i].y += 80 // Fall down
                    particles[i].opacity = 0
                    particles[i].scale = 0.3
                    particles[i].rotation += Double.random(in: 90...180)
                }
            }
        }

        // Cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            particles = []
            onComplete()
        }
    }

    private var confettiColors: [Color] {
        [
            .yellow,
            .orange,
            .green,
            .blue,
            .purple,
            .pink,
            .red,
            .cyan,
            .mint,
            .indigo
        ]
    }
}

/// Type-erased shape for varied confetti
private struct AnyShape: Shape {
    private let _path: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        _path = { rect in
            shape.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

private struct DesktopConfettiParticle: Identifiable {
    let id: UUID
    let color: Color
    let size: CGFloat
    let aspectRatio: CGFloat
    var x: CGFloat
    var y: CGFloat
    let targetX: CGFloat
    let targetY: CGFloat
    var opacity: Double
    var scale: CGFloat
    var rotation: Double
    let targetRotation: Double
    let shape: AnyShape
}
