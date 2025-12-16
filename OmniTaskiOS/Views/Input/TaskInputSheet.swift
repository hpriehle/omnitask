import SwiftUI
import OmniTaskCore

struct TaskInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var environment: AppEnvironmentiOS
    @EnvironmentObject var taskRepository: TaskRepository
    @EnvironmentObject var projectRepository: ProjectRepository

    let preselectedProject: Project?

    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var showingManualEntry = false

    init(preselectedProject: Project? = nil) {
        self.preselectedProject = preselectedProject
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // AI Input Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Describe your task")
                        .font(.headline)

                    Text("Use natural language like \"Call mom tomorrow\" or \"Finish report by Friday high priority\"")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("What do you need to do?", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                        .disabled(isProcessing)

                    HStack {
                        Button {
                            processTask()
                        } label: {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(isProcessing ? "Processing..." : "Create Task")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputText.isEmpty || isProcessing)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // Manual Entry Option
                Button {
                    showingManualEntry = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("Enter details manually")
                    }
                }
                .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualTaskEntrySheet(preselectedProject: preselectedProject)
            }
        }
    }

    private func processTask() {
        guard !inputText.isEmpty else { return }
        isProcessing = true

        Task {
            do {
                let tasks = try await environment.taskStructuringService.parseInput(
                    inputText,
                    defaultToToday: false,
                    defaultProjectId: preselectedProject?.id
                )

                // Create all parsed tasks
                for task in tasks {
                    try await taskRepository.create(task)
                }
                dismiss()
            } catch {
                // Fallback to simple task creation
                let simpleTask = OmniTask(
                    title: inputText,
                    projectId: preselectedProject?.id
                )
                try? await taskRepository.create(simpleTask)
                dismiss()
            }
        }
    }
}

struct ManualTaskEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var taskRepository: TaskRepository
    @EnvironmentObject var projectRepository: ProjectRepository

    let preselectedProject: Project?

    @State private var title = ""
    @State private var notes = ""
    @State private var selectedProjectId: String?
    @State private var priority: Priority = .medium
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    init(preselectedProject: Project? = nil) {
        self.preselectedProject = preselectedProject
        _selectedProjectId = State(initialValue: preselectedProject?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $title)

                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("Notes (optional)")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
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
                        ForEach(Priority.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                }

                Section {
                    Toggle("Due Date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTask()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func createTask() {
        Task {
            let task = OmniTask(
                title: title,
                notes: notes.isEmpty ? nil : notes,
                projectId: selectedProjectId,
                priority: priority,
                dueDate: hasDueDate ? dueDate : nil
            )
            try? await taskRepository.create(task)
            dismiss()
        }
    }
}

#Preview {
    TaskInputSheet()
        .environmentObject(AppEnvironmentiOS())
}
