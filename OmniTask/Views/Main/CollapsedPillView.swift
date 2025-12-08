import SwiftUI

/// Collapsed state of the floating pill - minimal indicator with task count or current task
struct CollapsedPillView: View {
    @Binding var isExpanded: Bool
    let taskCount: Int
    @ObservedObject var taskListVM: TaskListViewModel
    @ObservedObject var taskInputVM: TaskInputViewModel
    var onHide: ((TimeInterval?) -> Void)?
    var onSizeChange: ((CGSize) -> Void)?

    @State private var isHovered = false
    @State private var successCheckScale: CGFloat = 0
    @State private var showingHideMenu = false
    @State private var isCompletingTask = false
    @State private var showPillConfetti = false

    /// Width when showing current task
    private let currentTaskWidth: CGFloat = 220
    /// Width when showing task count only
    private let normalWidth: CGFloat = 100
    /// Height is constant
    private let pillHeight: CGFloat = 36

    /// Current visual state of the pill
    private enum PillState {
        case normal
        case currentTask
        case recording
        case processing
        case success
    }

    private var currentState: PillState {
        if taskInputVM.showSuccess {
            return .success
        } else if taskInputVM.isProcessing {
            return .processing
        } else if taskInputVM.isRecording {
            return .recording
        } else if taskListVM.currentTask != nil {
            return .currentTask
        }
        return .normal
    }

    private var pillWidth: CGFloat {
        switch currentState {
        case .currentTask:
            return currentTaskWidth
        default:
            return normalWidth
        }
    }

    var body: some View {
        ZStack {
            switch currentState {
            case .normal:
                normalContent
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))

            case .currentTask:
                currentTaskContent
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))

            case .recording:
                recordingContent
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))

            case .processing:
                processingContent
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))

            case .success:
                successContent
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: currentState)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: pillWidth, height: pillHeight)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .overlay {
            Capsule()
                .strokeBorder(borderColor, lineWidth: 0.5)
        }
        .contentShape(Capsule())
        .onTapGesture {
            // Only allow expansion when not recording/processing
            guard currentState == .normal || currentState == .success || currentState == .currentTask else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded = true
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: pillWidth) { newWidth in
            onSizeChange?(CGSize(width: newWidth, height: pillHeight))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pillWidth)
    }

    // MARK: - State Views

    private var normalContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.accentColor)

            if taskCount > 0 {
                Text("\(taskCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 4)

            hideMenuButton
        }
    }

    private var currentTaskContent: some View {
        HStack(spacing: 8) {
            // Checkbox always visible for current task
            Button {
                completeCurrentTask()
            } label: {
                Image(systemName: isCompletingTask ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isCompletingTask ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // Task title with marquee
            if let task = taskListVM.currentTask {
                MarqueeText(
                    text: task.title,
                    font: .system(size: 12, weight: .medium),
                    containerWidth: currentTaskWidth - 60,
                    isHovered: $isHovered
                )
                .frame(height: 16)
            }

            hideMenuButton
        }
        .overlay {
            // Internal pill confetti
            ConfettiView(isShowing: $showPillConfetti, particleCount: 15)
        }
    }

    private var hideMenuButton: some View {
        Button {
            showingHideMenu = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .opacity(isHovered ? 1 : 0.5)
        .popover(isPresented: $showingHideMenu, arrowEdge: .bottom) {
            HideMenuView(
                onHideForHour: {
                    showingHideMenu = false
                    onHide?(60 * 60)
                },
                onHideUntilMorning: {
                    showingHideMenu = false
                    onHide?(calculateMorningInterval())
                },
                onClose: {
                    showingHideMenu = false
                }
            )
        }
    }

    private func completeCurrentTask() {
        guard !isCompletingTask else { return }
        print("[CollapsedPillView] completeCurrentTask triggered")

        isCompletingTask = true
        showPillConfetti = true  // Trigger internal pill confetti
        print("[CollapsedPillView] Starting completion animation, showPillConfetti = true")

        // Delay to show the check animation, then complete
        // Confetti is triggered by TaskListViewModel.completeCurrentTask()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task {
                print("[CollapsedPillView] Calling taskListVM.completeCurrentTask()")
                await taskListVM.completeCurrentTask()
                print("[CollapsedPillView] taskListVM.completeCurrentTask() returned")
                // Reset after ViewModel completes (which includes confetti delay)
                showPillConfetti = false
                isCompletingTask = false
                print("[CollapsedPillView] Completion finished, reset state")
            }
        }
    }

    private var recordingContent: some View {
        HStack {
            Spacer()
            AudioWaveformView(
                audioLevel: taskInputVM.audioLevel,
                barCount: 5,
                barWidth: 3,
                barSpacing: 3,
                minHeight: 6,
                maxHeight: 18
            )
            Spacer()
        }
    }

    private var processingContent: some View {
        HStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 20, height: 20)
            Spacer()
        }
    }

    private var successContent: some View {
        HStack {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.green)
                .scaleEffect(successCheckScale)
                .onAppear {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        successCheckScale = 1.0
                    }
                }
                .onDisappear {
                    successCheckScale = 0
                }
            Spacer()
        }
    }

    // MARK: - Helpers

    private var borderColor: Color {
        switch currentState {
        case .recording:
            return .accentColor.opacity(0.5)
        case .success:
            return .green.opacity(0.5)
        default:
            return .secondary.opacity(0.3)
        }
    }

    private func calculateMorningInterval() -> TimeInterval {
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 8
        components.minute = 0
        var targetDate = calendar.date(from: components) ?? now
        if targetDate <= now {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? now
        }
        return targetDate.timeIntervalSince(now)
    }
}

// MARK: - Hide Menu

/// Popup menu for hide options
private struct HideMenuView: View {
    let onHideForHour: () -> Void
    let onHideUntilMorning: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with close button
            HStack {
                Text("Hide")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            // Hide options
            VStack(spacing: 0) {
                HideOptionButton(title: "Hide for 1 Hour", action: onHideForHour)
                HideOptionButton(title: "Hide Until Morning", action: onHideUntilMorning)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 160)
    }
}

private struct HideOptionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

// Note: Previews require mock TaskInputViewModel which isn't available in this context
// The view can be previewed via MainPillView or the running app
