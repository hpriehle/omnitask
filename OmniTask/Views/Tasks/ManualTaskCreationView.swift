import SwiftUI

/// Modal view for manually creating a new task
struct ManualTaskCreationView: View {
    let projects: [Project]
    let onCreate: (OmniTask) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var selectedProjectId: String?
    @State private var priority: Priority = .medium
    @State private var dueDate: Date = Date()
    @State private var hasDueDate = false
    @State private var isRecurring = false
    @State private var recurringFrequency: RecurringPattern.Frequency = .weekly

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("New Task")
                    .font(.headline)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Title
            TextField("Task title", text: $title)
                .textFieldStyle(.plain)
                .font(.headline)

            // Project picker
            HStack {
                Text("Project")
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $selectedProjectId) {
                    Text("None").tag(nil as String?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id as String?)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            // Priority picker
            HStack {
                Text("Priority")
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $priority) {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            // Due date
            HStack {
                Toggle("Due date", isOn: $hasDueDate)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Text("Due date")
                    .foregroundColor(.secondary)

                Spacer()

                if hasDueDate {
                    DatePicker(
                        "",
                        selection: $dueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .fixedSize()
                }
            }

            // Recurring
            if hasDueDate {
                HStack {
                    Toggle("Recurring", isOn: $isRecurring)
                        .toggleStyle(.switch)
                        .labelsHidden()

                    Text("Recurring")
                        .foregroundColor(.secondary)

                    Spacer()

                    if isRecurring {
                        Picker("", selection: $recurringFrequency) {
                            Text("Daily").tag(RecurringPattern.Frequency.daily)
                            Text("Weekly").tag(RecurringPattern.Frequency.weekly)
                            Text("Monthly").tag(RecurringPattern.Frequency.monthly)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            // Notes (description)
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .foregroundColor(.secondary)
                    .font(.caption)

                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 60)
                    .padding(4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
            }

            Spacer()

            // Action buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)

                Spacer()

                Button("Create Task") {
                    createTask()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding()
        .frame(width: 300, height: 400)
    }

    private func createTask() {
        var recurringPattern: RecurringPattern? = nil
        if isRecurring && hasDueDate {
            recurringPattern = RecurringPattern(frequency: recurringFrequency)
        }

        let task = OmniTask(
            title: title,
            notes: notes.isEmpty ? nil : notes,
            projectId: selectedProjectId,
            priority: priority,
            dueDate: hasDueDate ? dueDate : nil,
            recurringPattern: recurringPattern
        )

        onCreate(task)
    }
}

// MARK: - Preview

#Preview {
    ManualTaskCreationView(
        projects: [
            Project(name: "Work", color: "#3B82F6"),
            Project(name: "Personal", color: "#10B981")
        ],
        onCreate: { _ in },
        onCancel: {}
    )
}
