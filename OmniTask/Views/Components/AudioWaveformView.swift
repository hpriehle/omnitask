import SwiftUI

/// Animated waveform visualization that responds to audio levels
struct AudioWaveformView: View {
    let audioLevel: Float
    let barCount: Int
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    init(
        audioLevel: Float,
        barCount: Int = 5,
        barWidth: CGFloat = 3,
        barSpacing: CGFloat = 2,
        minHeight: CGFloat = 4,
        maxHeight: CGFloat = 20
    ) {
        self.audioLevel = audioLevel
        self.barCount = barCount
        self.barWidth = barWidth
        self.barSpacing = barSpacing
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    audioLevel: audioLevel,
                    index: index,
                    barCount: barCount,
                    barWidth: barWidth,
                    minHeight: minHeight,
                    maxHeight: maxHeight
                )
            }
        }
    }
}

/// Individual bar in the waveform
private struct WaveformBar: View {
    let audioLevel: Float
    let index: Int
    let barCount: Int
    let barWidth: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    @State private var animatedHeight: CGFloat = 4

    private var targetHeight: CGFloat {
        // Create wave effect by offsetting each bar's response
        let centerIndex = Float(barCount) / 2
        let distanceFromCenter = abs(Float(index) - centerIndex)
        let centerWeight = 1.0 - (distanceFromCenter / centerIndex) * 0.4

        let level = CGFloat(audioLevel * centerWeight)
        return minHeight + (maxHeight - minHeight) * level
    }

    var body: some View {
        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(Color.accentColor)
            .frame(width: barWidth, height: animatedHeight)
            .onChange(of: audioLevel) { _ in
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    animatedHeight = targetHeight
                }
            }
            .onAppear {
                animatedHeight = targetHeight
            }
    }
}

// MARK: - Preview

#Preview("Active") {
    struct PreviewWrapper: View {
        @State private var level: Float = 0.5

        var body: some View {
            VStack(spacing: 20) {
                AudioWaveformView(audioLevel: level)
                    .frame(height: 24)

                Slider(value: $level, in: 0...1)
                    .padding(.horizontal)

                Text("Level: \(String(format: "%.2f", level))")
                    .font(.caption)
            }
            .padding()
            .frame(width: 200)
        }
    }

    return PreviewWrapper()
}

#Preview("In Pill") {
    struct PillPreview: View {
        @State private var level: Float = 0.6

        var body: some View {
            HStack {
                AudioWaveformView(audioLevel: level)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 100, height: 36)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
            .overlay {
                Capsule()
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            }
            .onAppear {
                // Simulate audio level changes
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    level = Float.random(in: 0.2...0.9)
                }
            }
        }
    }

    return PillPreview()
        .padding()
        .background(Color.gray.opacity(0.3))
}
