import SwiftUI

/// A text view that scrolls horizontally when content exceeds container width
/// Used in the collapsed pill to show long task titles with a carousel effect
struct MarqueeText: View {
    let text: String
    let font: Font
    let containerWidth: CGFloat

    /// Speed in points per second
    var speed: CGFloat = 30
    /// Delay before starting scroll (in seconds)
    var startDelay: TimeInterval = 1.0
    /// Pause at each end (in seconds)
    var endPause: TimeInterval = 1.5

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isAnimating = false
    @Binding var isHovered: Bool

    private var needsScroll: Bool {
        textWidth > containerWidth
    }

    private var scrollDistance: CGFloat {
        max(0, textWidth - containerWidth + 8) // +8 for padding
    }

    private var scrollDuration: TimeInterval {
        Double(scrollDistance / speed)
    }

    var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { textGeometry in
                        Color.clear
                            .onAppear {
                                textWidth = textGeometry.size.width
                            }
                            .onChange(of: text) { _ in
                                textWidth = textGeometry.size.width
                            }
                    }
                )
                .offset(x: offset)
        }
        .frame(width: containerWidth, alignment: .leading)
        .clipped()
        .onChange(of: isHovered) { hovering in
            if hovering && needsScroll {
                startScrollAnimation()
            } else {
                stopScrollAnimation()
            }
        }
    }

    private func startScrollAnimation() {
        guard needsScroll else { return }

        offset = 0
        isAnimating = true

        // Initial delay before starting
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            guard isHovered else { return }
            animateForward()
        }
    }

    private func animateForward() {
        guard isHovered, isAnimating else { return }

        withAnimation(.linear(duration: scrollDuration)) {
            offset = -scrollDistance
        }

        // After reaching end, pause then go back
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollDuration + endPause) {
            guard isHovered, isAnimating else { return }
            animateBackward()
        }
    }

    private func animateBackward() {
        guard isHovered, isAnimating else { return }

        withAnimation(.linear(duration: scrollDuration)) {
            offset = 0
        }

        // After reaching start, pause then forward again
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollDuration + endPause) {
            guard isHovered, isAnimating else { return }
            animateForward()
        }
    }

    private func stopScrollAnimation() {
        isAnimating = false
        withAnimation(.easeOut(duration: 0.2)) {
            offset = 0
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Short text - no scroll
        MarqueeText(
            text: "Short task",
            font: .system(size: 12, weight: .medium),
            containerWidth: 150,
            isHovered: .constant(true)
        )
        .frame(height: 20)
        .background(Color.gray.opacity(0.2))

        // Long text - should scroll
        MarqueeText(
            text: "This is a very long task title that should scroll when hovered",
            font: .system(size: 12, weight: .medium),
            containerWidth: 150,
            isHovered: .constant(true)
        )
        .frame(height: 20)
        .background(Color.gray.opacity(0.2))
    }
    .padding()
}
