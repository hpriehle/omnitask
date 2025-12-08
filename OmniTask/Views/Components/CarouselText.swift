import SwiftUI

/// A text view that scrolls continuously in a loop when content exceeds container width
/// Shows: [Text] --- gap --- [Text copy] scrolling left infinitely
struct CarouselText: View {
    let text: String
    let font: Font
    let containerWidth: CGFloat

    /// Gap between text copies
    var gapWidth: CGFloat = 40
    /// Speed in points per second
    var speed: CGFloat = 25
    /// Delay before starting scroll
    var startDelay: TimeInterval = 0.5

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isAnimating = false
    @Binding var isHovered: Bool

    private var needsScroll: Bool {
        textWidth > containerWidth
    }

    /// Total width of one "unit" (text + gap)
    private var unitWidth: CGFloat {
        textWidth + gapWidth
    }

    /// Duration to scroll one full unit
    private var scrollDuration: TimeInterval {
        Double(unitWidth / speed)
    }

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: gapWidth) {
                // First copy
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(measureText)

                // Second copy (only if scrolling needed)
                if needsScroll {
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .offset(x: offset)
        }
        .frame(width: containerWidth, alignment: .leading)
        .clipped()
        .onChange(of: isHovered) { hovering in
            if hovering && needsScroll {
                startCarousel()
            } else {
                stopCarousel()
            }
        }
    }

    private var measureText: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { textWidth = geo.size.width }
                .onChange(of: text) { _ in textWidth = geo.size.width }
        }
    }

    private func startCarousel() {
        guard needsScroll else { return }

        offset = 0
        isAnimating = true

        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            guard isHovered else { return }
            animateLoop()
        }
    }

    private func animateLoop() {
        guard isHovered, isAnimating else { return }

        // Animate to scroll one full unit
        withAnimation(.linear(duration: scrollDuration)) {
            offset = -unitWidth
        }

        // When done, instantly reset and loop
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollDuration) {
            guard isHovered, isAnimating else { return }
            offset = 0 // Instant reset (no animation)
            animateLoop() // Continue loop
        }
    }

    private func stopCarousel() {
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
        CarouselText(
            text: "Short task",
            font: .system(size: 13),
            containerWidth: 150,
            isHovered: .constant(true)
        )
        .frame(height: 16)
        .background(Color.gray.opacity(0.2))

        // Long text - should scroll
        CarouselText(
            text: "This is a very long subtask title that should scroll continuously when hovered",
            font: .system(size: 13),
            containerWidth: 150,
            isHovered: .constant(true)
        )
        .frame(height: 16)
        .background(Color.gray.opacity(0.2))
    }
    .padding()
}
