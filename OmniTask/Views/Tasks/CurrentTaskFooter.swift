import SwiftUI

/// Sticky footer showing the current task with yellow border
/// Always visible at the bottom of the task list regardless of tab or scroll position
struct CurrentTaskFooter: View {
    let task: OmniTask
    let projects: [Project]
    let onComplete: () async -> Bool
    let onEdit: () -> Void
    let onUnstar: () -> Void

    // Subtask support
    var subtaskCount: (total: Int, completed: Int)?
    var subtasks: [OmniTask]
    var isExpanded: Bool
    var onToggleExpand: (() -> Void)?
    var onCompleteSubtask: ((OmniTask) -> Void)?
    var onUpdateSubtask: ((OmniTask) -> Void)?

    // Keyboard navigation
    var isKeyboardSelected: Bool = false

    // Completion validation
    var canComplete: Bool = true

    @State private var isHovered = false
    @State private var isCompleting = false
    @State private var showingDetail = false
    @State private var editableTask: OmniTask

    init(
        task: OmniTask,
        projects: [Project],
        onComplete: @escaping () async -> Bool,
        onEdit: @escaping () -> Void,
        onUnstar: @escaping () -> Void = {},
        subtaskCount: (total: Int, completed: Int)? = nil,
        subtasks: [OmniTask] = [],
        isExpanded: Bool = false,
        onToggleExpand: (() -> Void)? = nil,
        onCompleteSubtask: ((OmniTask) -> Void)? = nil,
        onUpdateSubtask: ((OmniTask) -> Void)? = nil,
        isKeyboardSelected: Bool = false,
        canComplete: Bool = true
    ) {
        self.task = task
        self.projects = projects
        self.onComplete = onComplete
        self.onEdit = onEdit
        self.onUnstar = onUnstar
        self.subtaskCount = subtaskCount
        self.subtasks = subtasks
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
        self.onCompleteSubtask = onCompleteSubtask
        self.onUpdateSubtask = onUpdateSubtask
        self.isKeyboardSelected = isKeyboardSelected
        self.canComplete = canComplete
        self._editableTask = State(initialValue: task)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main footer row
            HStack(alignment: .center, spacing: 10) {
                // Checkbox
                Button(action: completeWithAnimation) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(task.isCompleted ? .green : (canComplete ? .secondary : .secondary.opacity(0.5)))
                        .scaleEffect(isCompleting ? 1.2 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(isCompleting || !canComplete)
                .help(canComplete ? "" : "Complete all subtasks first")

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // Project dot
                        projectDot

                        // Title
                        Text(task.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        // Recurring indicator
                        if task.isRecurring {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Due date if present
                    if let dueDate = task.dueDate {
                        Text(formatDueDate(dueDate))
                            .font(.system(size: 11))
                            .foregroundColor(task.isOverdue ? .red : .secondary)
                    }
                }

                Spacer()

                // Subtask progress badge
                if let count = subtaskCount, count.total > 0 {
                    Text("\(count.completed)/\(count.total)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(count.completed == count.total ? .green : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(count.completed == count.total ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                        )
                }

                // Current task indicator (star) - tappable to unstar
                Button {
                    onUnstar()
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.yellow)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from current task")

                // Expand/collapse chevron (always visible if has subtasks)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                editableTask = task
                showingDetail = true
            }

            // Subtasks (when expanded)
            if isExpanded, let count = subtaskCount, count.total > 0 {
                ForEach(subtasks) { subtask in
                    SubtaskRowView(
                        task: subtask,
                        projects: projects,
                        onComplete: { onCompleteSubtask?(subtask) },
                        onUpdate: { onUpdateSubtask?($0) },
                        onDelete: {}
                    )
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isKeyboardSelected ? Color.yellow.opacity(0.15) : Color.yellow.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isKeyboardSelected ? Color.accentColor : Color.yellow.opacity(0.5), lineWidth: isKeyboardSelected ? 2 : 1.5)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .opacity(isCompleting ? 0.5 : 1.0)
        .sheet(isPresented: $showingDetail) {
            TaskDetailView(
                task: $editableTask,
                projects: projects,
                tagRepository: nil,
                onSave: { updatedTask in
                    onEdit()
                    showingDetail = false
                },
                onCancel: {
                    showingDetail = false
                }
            )
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var projectDot: some View {
        if let projectId = task.projectId,
           let project = projects.first(where: { $0.id == projectId }),
           let colorHex = project.color {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
        }
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today \(formatter.string(from: date))"
        }

        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }

        let formatter = DateFormatter()
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateFormat = "MMM d"
        }

        return formatter.string(from: date)
    }

    // MARK: - Actions

    private func completeWithAnimation() {
        // Don't start if can't complete
        guard canComplete else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isCompleting = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            let success = await onComplete()
            if !success {
                await MainActor.run {
                    withAnimation {
                        isCompleting = false // Reset on failure
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let projects = [
        Project(name: "Work", color: "#3B82F6"),
        Project(name: "Personal", color: "#10B981")
    ]

    return VStack {
        Spacer()

        CurrentTaskFooter(
            task: OmniTask(
                title: "Complete the current task feature implementation",
                projectId: projects[0].id,
                dueDate: Date()
            ),
            projects: projects,
            onComplete: { return true },
            onEdit: {}
        )
        .padding()
    }
    .frame(width: 340, height: 400)
}
