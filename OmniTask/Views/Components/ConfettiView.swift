import SwiftUI

/// A confetti burst animation for celebrating task completion
struct ConfettiView: View {
    @Binding var isShowing: Bool

    /// Duration of the confetti animation
    var duration: TimeInterval = 1.0
    /// Number of confetti particles
    var particleCount: Int = 20

    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
                    .scaleEffect(particle.scale)
            }
        }
        .onChange(of: isShowing) { showing in
            if showing {
                triggerConfetti()
            }
        }
    }

    private func triggerConfetti() {
        // Generate particles
        particles = (0..<particleCount).map { _ in
            ConfettiParticle(
                id: UUID(),
                color: confettiColors.randomElement() ?? .yellow,
                size: CGFloat.random(in: 4...8),
                x: 0,
                y: 0,
                targetX: CGFloat.random(in: -60...60),
                targetY: CGFloat.random(in: -80...(-20)),
                opacity: 1.0,
                scale: 1.0
            )
        }

        // Animate particles outward
        withAnimation(.easeOut(duration: duration * 0.6)) {
            for i in particles.indices {
                particles[i].x = particles[i].targetX
                particles[i].y = particles[i].targetY
            }
        }

        // Fade out and fall
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.4) {
            withAnimation(.easeIn(duration: duration * 0.6)) {
                for i in particles.indices {
                    particles[i].y += 40
                    particles[i].opacity = 0
                    particles[i].scale = 0.5
                }
            }
        }

        // Clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            particles = []
            isShowing = false
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
            .cyan
        ]
    }
}

private struct ConfettiParticle: Identifiable {
    let id: UUID
    let color: Color
    let size: CGFloat
    var x: CGFloat
    var y: CGFloat
    let targetX: CGFloat
    let targetY: CGFloat
    var opacity: Double
    var scale: CGFloat
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var showConfetti = false

        var body: some View {
            VStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .frame(width: 200, height: 40)

                    Text("Complete Task")
                        .font(.system(size: 14, weight: .medium))

                    ConfettiView(isShowing: $showConfetti)
                }

                Button("Trigger Confetti") {
                    showConfetti = true
                }
                .padding(.top, 40)
            }
            .frame(width: 300, height: 200)
        }
    }

    return PreviewWrapper()
}
