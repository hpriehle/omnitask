import SwiftUI
import OmniTaskCore

struct TaskDetailView: View {
    let task: OmniTask
    @EnvironmentObject var taskRepository: TaskRepository
    @EnvironmentObject var projectRepository: ProjectRepository
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var selectedProjectId: String?
    @State private var priority: Priority
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool

    init(task: OmniTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes ?? "")
        _selectedProjectId = State(initialValue: task.projectId)
        _priority = State(initialValue: task.priority)
        _dueDate = State(initialValue: task.dueDate)
        _hasDueDate = State(initialValue: task.dueDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)

                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                Section {
                    Picker("Project", selection: $selectedProjectId) {
                        Text("None").tag(nil as String?)
                        ForEach(projectRepository.projects) { project in
                            HStack {
                                Circle()
                                    .fill(project.swiftUIColor)
                                    .frame(width: 10, height: 10)
                                Text(project.name)
                            }
                            .tag(project.id as String?)
                        }
                    }

                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                }

                Section {
                    Toggle("Due Date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker(
                            "Date",
                            selection: Binding(
                                get: { dueDate ?? Date() },
                                set: { dueDate = $0 }
                            ),
                            displayedComponents: [.date]
                        )
                    }
                }

                if task.recurringPattern != nil {
                    Section {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text(task.recurringPattern!.displayString)
                        }
                        .foregroundColor(.secondary)
                    } header: {
                        Text("Recurrence")
                    }
                }

                Section {
                    Button(task.isCurrentTask ? "Stop Focus" : "Set as Current") {
                        toggleCurrentTask()
                    }
                    .foregroundColor(task.isCurrentTask ? .orange : .blue)

                    Button(task.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                        toggleCompletion()
                    }
                    .foregroundColor(.green)

                    Button("Delete Task", role: .destructive) {
                        deleteTask()
                    }
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTask()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func saveTask() {
        Task {
            var updated = task
            updated.title = title
            updated.notes = notes.isEmpty ? nil : notes
            updated.projectId = selectedProjectId
            updated.priority = priority
            updated.dueDate = hasDueDate ? dueDate : nil
            updated.updatedAt = Date()
            try? await taskRepository.update(updated)
            dismiss()
        }
    }

    private func toggleCurrentTask() {
        Task {
            if task.isCurrentTask {
                var updated = task
                updated.isCurrentTask = false
                try? await taskRepository.update(updated)
            } else {
                // Clear existing current task
                for existingTask in taskRepository.tasks where existingTask.isCurrentTask {
                    var cleared = existingTask
                    cleared.isCurrentTask = false
                    try? await taskRepository.update(cleared)
                }

                var updated = task
                updated.isCurrentTask = true
                try? await taskRepository.update(updated)
            }
            dismiss()
        }
    }

    private func toggleCompletion() {
        Task {
            var updated = task
            updated.isCompleted.toggle()
            updated.completedAt = updated.isCompleted ? Date() : nil
            if updated.isCompleted {
                updated.isCurrentTask = false
            }
            try? await taskRepository.update(updated)
            dismiss()
        }
    }

    private func deleteTask() {
        Task {
            try? await taskRepository.delete(task)
            dismiss()
        }
    }
}

#Preview {
    TaskDetailView(task: OmniTask(title: "Sample Task"))
        .environmentObject(TaskRepository(database: DatabaseManager()))
        .environmentObject(ProjectRepository(database: DatabaseManager()))
}
