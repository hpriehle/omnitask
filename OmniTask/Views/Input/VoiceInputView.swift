import SwiftUI

/// Animated voice recording indicator
struct VoiceInputView: View {
    let isRecording: Bool

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Pulsing background
            Circle()
                .fill(Color.red.opacity(0.3))
                .frame(width: 24, height: 24)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 0.5)

            // Main icon
            Circle()
                .fill(Color.red)
                .frame(width: 16, height: 16)
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                }
        }
        .frame(width: 24, height: 24)
        .onAppear {
            if isRecording {
                startPulsing()
            }
        }
        .onChange(of: isRecording) { newValue in
            if newValue {
                startPulsing()
            } else {
                isPulsing = false
            }
        }
    }

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
            isPulsing = true
        }
    }
}

// MARK: - Preview

#Preview("Recording") {
    VStack(spacing: 20) {
        VoiceInputView(isRecording: true)

        HStack {
            Text("Recording...")
                .font(.caption)
                .foregroundColor(.secondary)

            VoiceInputView(isRecording: true)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    .padding()
}

#Preview("Not Recording") {
    VoiceInputView(isRecording: false)
        .padding()
}
