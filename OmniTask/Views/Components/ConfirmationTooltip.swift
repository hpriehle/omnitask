import SwiftUI

/// A tooltip component that appears when awaiting confirmation for task completion
struct ConfirmationTooltip: View {
    let message: String
    let isVisible: Bool

    var body: some View {
        if isVisible {
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.5), lineWidth: 0.5)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ConfirmationTooltip(message: "Click again to complete with subtasks", isVisible: true)
        ConfirmationTooltip(message: "Click again to complete with subtasks", isVisible: false)
    }
    .padding()
}
