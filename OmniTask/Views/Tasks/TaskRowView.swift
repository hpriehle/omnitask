import SwiftUI
import OmniTaskCore

/// Single task row with checkbox, title, and metadata
struct TaskRowView: View {
    let task: OmniTask
    let projects: [OmniTaskCore.Project]
    var tagRepository: TagRepository?
    var isSelected: Bool = false
    let onComplete: () -> Void
    let onUpdate: (OmniTask) -> Void

    // Subtask support
    var subtasks: [OmniTask] = []
    var subtaskCount: (total: Int, completed: Int)?
    var isExpanded: Bool = false
    var canComplete: Bool = true
    var isPendingConfirmation: Bool = false // Waiting for second click to confirm completion
    var onToggleExpand: (() -> Void)?
    var onAddSubtask: (() -> Void)?

    // Quick date action
    var isInTodayView: Bool = false
    var onQuickDateAction: (() -> Void)?

    // Current task support
    var isCurrentTask: Bool = false
    var onSetCurrentTask: (() -> Void)?

    // Show project dot instead of priority (for Today view)
    var showProjectDot: Bool = false

    // Keyboard navigation
    var isKeyboardSelected: Bool = false

    @State private var isHovered = false
    @State private var isCompleting = false
    @State private var showConfetti = false
    @State private var showingDetail = false
    @State private var editableTask: OmniTask

    init(
        task: OmniTask,
        projects: [Project],
        tagRepository: TagRepository? = nil,
        isSelected: Bool = false,
        subtasks: [OmniTask] = [],
        subtaskCount: (total: Int, completed: Int)? = nil,
        isExpanded: Bool = false,
        canComplete: Bool = true,
        isPendingConfirmation: Bool = false,
        onComplete: @escaping () -> Void,
        onUpdate: @escaping (OmniTask) -> Void,
        onToggleExpand: (() -> Void)? = nil,
        onAddSubtask: (() -> Void)? = nil,
        isInTodayView: Bool = false,
        onQuickDateAction: (() -> Void)? = nil,
        isCurrentTask: Bool = false,
        onSetCurrentTask: (() -> Void)? = nil,
        showProjectDot: Bool = false,
        isKeyboardSelected: Bool = false
    ) {
        self.task = task
        self.projects = projects
        self.tagRepository = tagRepository
        self.isSelected = isSelected
        self.subtasks = subtasks
        self.subtaskCount = subtaskCount
        self.isExpanded = isExpanded
        self.canComplete = canComplete
        self.isPendingConfirmation = isPendingConfirmation
        self.onComplete = onComplete
        self.onUpdate = onUpdate
        self.onToggleExpand = onToggleExpand
        self.onAddSubtask = onAddSubtask
        self.isInTodayView = isInTodayView
        self.onQuickDateAction = onQuickDateAction
        self.isCurrentTask = isCurrentTask
        self.onSetCurrentTask = onSetCurrentTask
        self.showProjectDot = showProjectDot
        self.isKeyboardSelected = isKeyboardSelected
        self._editableTask = State(initialValue: task)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Checkbox with confetti overlay
            ZStack {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(task.isCompleted ? .green : checkboxColor)
                    .scaleEffect(isCompleting ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCompleting)
                    .animation(.easeInOut(duration: 0.2), value: task.isCompleted)

                ConfettiView(isShowing: $showConfetti, particleCount: 12)
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .onTapGesture {
                completeWithAnimation()
            }

            // Content (tappable area for edit)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Project dot (shown in Today view instead of priority)
                    if showProjectDot {
                        projectDot
                    } else if task.priority != .none && task.priority != .medium {
                        // Priority indicator (hidden in Today view)
                        priorityBadge
                    }

                    // Title
                    Text(task.title)
                        .font(.system(size: 14))
                        .foregroundColor(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted)
                        .lineLimit(2)
                        .animation(.easeInOut(duration: 0.25), value: task.isCompleted)

                    // Recurring indicator
                    if task.isRecurring {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                // Metadata row
                if task.dueDate != nil || task.notes != nil {
                    HStack(spacing: 8) {
                        if let dueDate = task.dueDate {
                            dueDateLabel(dueDate)
                        }

                        if task.notes != nil {
                            Image(systemName: "note.text")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                editableTask = task
                showingDetail = true
            }

            Spacer()

            // Subtask progress badge
            if let count = subtaskCount, count.total > 0 {
                subtaskProgressBadge(completed: count.completed, total: count.total)
            }

            // Right-side actions: hover buttons + caret (always visible if has subtasks)
            HStack(spacing: 2) {
                // Action buttons (on hover)
                if isHovered {
                    // Set as current task (star button)
                    if !task.isSubtask {
                        Button {
                            onSetCurrentTask?()
                        } label: {
                            Image(systemName: isCurrentTask ? "star.fill" : "star")
                                .font(.system(size: 14))
                                .foregroundColor(isCurrentTask ? .yellow : .secondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isCurrentTask ? "Current task" : "Set as current task")
                    }

                    // Quick date action (context-dependent)
                    Button {
                        onQuickDateAction?()
                    } label: {
                        Image(systemName: isInTodayView ? "arrow.right.circle" : "calendar.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isInTodayView ? "Defer to tomorrow" : "Move to today")

                    // Add subtask button (only for parent tasks)
                    if !task.isSubtask {
                        Button {
                            onAddSubtask?()
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Add subtask")
                    }
                }

                // Expand/collapse caret (always visible if has subtasks)
                if let count = subtaskCount, count.total > 0 {
                    Button {
                        onToggleExpand?()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(keyboardSelectionBackground)
        }
        .overlay {
            if isKeyboardSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            let _ = print("[TaskRowView] contextMenu opened for task: '\(task.title)', subtasks.count: \(subtasks.count)")
            TaskContextMenu(
                task: task,
                subtasks: subtasks,
                projects: projects,
                onUpdate: onUpdate
            )
        }
        .overlay(alignment: .bottomLeading) {
            ConfirmationTooltip(
                message: "Click again to complete with subtasks",
                isVisible: isPendingConfirmation
            )
            .offset(x: 4, y: 4)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.2), value: isPendingConfirmation)
        }
        .sheet(isPresented: $showingDetail) {
            TaskDetailView(
                task: $editableTask,
                projects: projects,
                tagRepository: tagRepository,
                onSave: { updatedTask in
                    print("[TaskRowView] onSave called with updated task: \(updatedTask.title)")
                    print("[TaskRowView] Updated task ID: \(updatedTask.id)")
                    print("[TaskRowView] Updated priority: \(updatedTask.priority.displayName)")
                    print("[TaskRowView] Updated dueDate: \(updatedTask.dueDate?.description ?? "nil")")
                    print("[TaskRowView] Updated projectId: \(updatedTask.projectId ?? "nil")")
                    onUpdate(updatedTask)
                    showingDetail = false
                },
                onCancel: {
                    print("[TaskRowView] Edit cancelled")
                    showingDetail = false
                }
            )
        }
    }

    // MARK: - Components

    private var checkboxColor: Color {
        if isPendingConfirmation {
            return .orange
        }
        return .secondary
    }

    private var keyboardSelectionBackground: Color {
        if isKeyboardSelected {
            return Color.accentColor.opacity(0.15)
        } else if isSelected {
            return Color.accentColor.opacity(0.1)
        }
        return Color.clear
    }

    private func subtaskProgressBadge(completed: Int, total: Int) -> some View {
        let isAllDone = completed == total
        return Text("\(completed)/\(total)")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isAllDone ? .green : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isAllDone ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
            )
    }

    private var priorityBadge: some View {
        Group {
            switch task.priority {
            case .urgent:
                Image(systemName: "exclamationmark.2")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red)
            case .high:
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
            case .low:
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
            default:
                EmptyView()
            }
        }
    }

    /// Colored dot representing the task's project
    @ViewBuilder
    private var projectDot: some View {
        if let projectId = task.projectId,
           let project = projects.first(where: { $0.id == projectId }),
           let colorHex = project.color {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 8, height: 8)
        } else {
            // No project or no color - show gray dot
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
        }
    }

    private func dueDateLabel(_ date: Date) -> some View {
        let formattedDate = formatDueDate(date)
        print("[TaskRowView] dueDateLabel - date: \(date), formatted: '\(formattedDate)'")
        return Text(formattedDate)
            .font(.system(size: 11))
            .foregroundColor(task.isOverdue ? .red : .secondary)
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            let result = "Today \(formatter.string(from: date))"
            print("[TaskRowView] formatDueDate - Today: '\(result)'")
            return result
        }

        if calendar.isDateInTomorrow(date) {
            print("[TaskRowView] formatDueDate - Tomorrow")
            return "Tomorrow"
        }

        let formatter = DateFormatter()
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateFormat = "MMM d"
        }

        let result = formatter.string(from: date)
        print("[TaskRowView] formatDueDate - Other: '\(result)'")
        return result
    }

    // MARK: - Actions

    private func completeWithAnimation() {
        print("[TaskRowView] completeWithAnimation called for task: '\(task.title)'")
        print("[TaskRowView] - task.id: \(task.id)")
        print("[TaskRowView] - isPendingConfirmation: \(isPendingConfirmation)")
        print("[TaskRowView] - subtaskCount: \(String(describing: subtaskCount))")
        print("[TaskRowView] - canComplete: \(canComplete)")

        // If uncompleting, just call onComplete without animation
        if task.isCompleted {
            print("[TaskRowView] Task is completed - uncompleting without animation")
            onComplete()
            return
        }

        // If already pending confirmation (second click), complete with animation
        if isPendingConfirmation {
            print("[TaskRowView] Second click detected - calling onComplete for confirmation with animation")
            triggerCompletionAnimation()
            // Delay onComplete to allow animation to show before row is removed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.onComplete()
            }
            return
        }

        // First click - let ViewModel decide if confirmation needed
        // If task has no subtasks, it completes and disappears
        // If task needs confirmation, ViewModel sets pendingCompletionTaskId
        // and view re-renders with tooltip + orange checkbox
        print("[TaskRowView] First click - calling onComplete with animation")
        triggerCompletionAnimation()
        // Delay onComplete to allow animation to show before row is removed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            print("[TaskRowView] Delayed onComplete now executing")
            self.onComplete()
        }
        print("[TaskRowView] onComplete scheduled")
    }

    private func triggerCompletionAnimation() {
        print("[TaskRowView] triggerCompletionAnimation called - isCompleting: \(isCompleting), showConfetti: \(showConfetti)")
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isCompleting = true
            print("[TaskRowView] isCompleting set to TRUE")
        }
        showConfetti = true
        print("[TaskRowView] showConfetti set to TRUE")

        // Reset scale after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            print("[TaskRowView] Resetting isCompleting to false")
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                self.isCompleting = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 8) {
        TaskRowView(
            task: OmniTask(
                title: "Urgent task with long title that wraps",
                priority: .urgent,
                dueDate: Date().addingTimeInterval(-3600)
            ),
            projects: [
                OmniTaskCore.Project(name: "Work", color: "#3B82F6"),
                OmniTaskCore.Project(name: "Personal", color: "#10B981")
            ],
            onComplete: {},
            onUpdate: { _ in }
        )

        TaskRowView(
            task: OmniTask(
                title: "High priority task",
                notes: "Some notes here",
                priority: .high,
                dueDate: Date()
            ),
            projects: [
                OmniTaskCore.Project(name: "Work", color: "#3B82F6"),
                OmniTaskCore.Project(name: "Personal", color: "#10B981")
            ],
            onComplete: {},
            onUpdate: { _ in }
        )

        TaskRowView(
            task: OmniTask(
                title: "Regular task",
                priority: .medium,
                recurringPattern: .daily
            ),
            projects: [
                OmniTaskCore.Project(name: "Work", color: "#3B82F6"),
                OmniTaskCore.Project(name: "Personal", color: "#10B981")
            ],
            onComplete: {},
            onUpdate: { _ in }
        )

        TaskRowView(
            task: OmniTask(
                title: "Completed task",
                priority: .low,
                isCompleted: true,
                completedAt: Date()
            ),
            projects: [
                OmniTaskCore.Project(name: "Work", color: "#3B82F6"),
                OmniTaskCore.Project(name: "Personal", color: "#10B981")
            ],
            onComplete: {},
            onUpdate: { _ in }
        )
    }
    .padding()
    .frame(width: 320)
}
