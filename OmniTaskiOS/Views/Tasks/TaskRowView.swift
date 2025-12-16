import SwiftUI
import UIKit
import OmniTaskCore

struct TaskRowView: View {
    let task: OmniTask
    @EnvironmentObject var taskRepository: TaskRepository
    @EnvironmentObject var projectRepository: ProjectRepository
    @State private var showingDetail = false

    var project: Project? {
        guard let projectId = task.projectId else { return nil }
        return projectRepository.projects.first { $0.id == projectId }
    }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 12) {
                // Completion checkbox
                Button {
                    toggleCompletion()
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.title)
                            .font(.body)
                            .strikethrough(task.isCompleted)
                            .foregroundColor(task.isCompleted ? .secondary : .primary)
                            .lineLimit(2)

                        if task.isCurrentTask {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }

                    HStack(spacing: 8) {
                        if let project = project {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(project.swiftUIColor)
                                    .frame(width: 8, height: 8)
                                Text(project.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let dueDate = task.dueDate {
                            HStack(spacing: 2) {
                                Image(systemName: "calendar")
                                Text(dueDate, style: .date)
                            }
                            .font(.caption)
                            .foregroundColor(isOverdue ? .red : .secondary)
                        }

                        if task.recurringPattern != nil {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Priority indicator
                if task.priority != .medium {
                    priorityIndicator
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            taskContextMenu
        }
        .swipeActions(edge: .leading) {
            Button {
                setAsCurrent()
            } label: {
                Label("Focus", systemImage: "star.fill")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteTask()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                toggleCompletion()
            } label: {
                Label(task.isCompleted ? "Undo" : "Complete", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(.green)
        }
        .sheet(isPresented: $showingDetail) {
            TaskDetailView(task: task)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Context Menu (3D Touch / Long Press)

    @ViewBuilder
    private var taskContextMenu: some View {
        // Copy button
        Button {
            copyTaskToClipboard()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Divider()

        // Set Priority submenu
        Menu {
            ForEach(Priority.allCases, id: \.self) { priority in
                Button {
                    setPriority(priority)
                } label: {
                    HStack {
                        if !priority.icon.isEmpty {
                            Image(systemName: priority.icon)
                        }
                        Text(priority.displayName)
                        if task.priority == priority {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Set Priority", systemImage: "flag")
        }

        // Move to Project submenu
        Menu {
            ForEach(projectRepository.projects) { project in
                Button {
                    moveToProject(project)
                } label: {
                    HStack {
                        Circle()
                            .fill(project.swiftUIColor)
                            .frame(width: 8, height: 8)
                        Text(project.name)
                        if task.projectId == project.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Move to Project", systemImage: "folder")
        }
    }

    private var isOverdue: Bool {
        guard let dueDate = task.dueDate else { return false }
        return dueDate < Date() && !task.isCompleted
    }

    @ViewBuilder
    private var priorityIndicator: some View {
        switch task.priority {
        case .urgent:
            Image(systemName: "exclamationmark.2")
                .font(.caption.bold())
                .foregroundColor(.red)
        case .high:
            Image(systemName: "exclamationmark")
                .font(.caption.bold())
                .foregroundColor(.orange)
        case .low:
            Image(systemName: "minus")
                .font(.caption)
                .foregroundColor(.secondary)
        default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func toggleCompletion() {
        Task {
            var updated = task
            updated.isCompleted.toggle()
            updated.completedAt = updated.isCompleted ? Date() : nil
            if updated.isCompleted {
                updated.isCurrentTask = false
            }
            try? await taskRepository.update(updated)
        }
    }

    private func setAsCurrent() {
        Task {
            // First clear any existing current task
            for existingTask in taskRepository.tasks where existingTask.isCurrentTask {
                var cleared = existingTask
                cleared.isCurrentTask = false
                try? await taskRepository.update(cleared)
            }

            // Set this task as current
            var updated = task
            updated.isCurrentTask = true
            try? await taskRepository.update(updated)
        }
    }

    private func deleteTask() {
        Task {
            try? await taskRepository.delete(task)
        }
    }

    private func copyTaskToClipboard() {
        var parts: [String] = [task.title]

        if task.priority != .none {
            parts.append("Priority: \(task.priority.displayName)")
        }

        if let dueDate = task.dueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append("Due: \(formatter.string(from: dueDate))")
        }

        if let notes = task.notes, !notes.isEmpty {
            parts.append(notes)
        }

        UIPasteboard.general.string = parts.joined(separator: "\n")
    }

    private func setPriority(_ priority: Priority) {
        Task {
            var updated = task
            updated.priority = priority
            try? await taskRepository.update(updated)
        }
    }

    private func moveToProject(_ project: Project) {
        Task {
            var updated = task
            updated.projectId = project.id
            try? await taskRepository.update(updated)
        }
    }
}

#Preview {
    List {
        TaskRowView(task: OmniTask(title: "Sample task", priority: .high))
    }
    .environmentObject(TaskRepository(database: DatabaseManager()))
    .environmentObject(ProjectRepository(database: DatabaseManager()))
}
