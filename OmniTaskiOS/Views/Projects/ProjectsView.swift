import SwiftUI
import OmniTaskCore

struct ProjectsView: View {
    @EnvironmentObject var environment: AppEnvironmentiOS
    @EnvironmentObject var projectRepository: ProjectRepository
    @EnvironmentObject var taskRepository: TaskRepository
    @State private var showingAddProject = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(projectRepository.projects) { project in
                    NavigationLink {
                        ProjectDetailView(project: project)
                    } label: {
                        ProjectRowView(project: project)
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddProject = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddProject) {
                AddProjectSheet()
            }
            .overlay {
                if projectRepository.projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "folder",
                        description: Text("Create a project to organize your tasks")
                    )
                }
            }
        }
    }
}

struct ProjectRowView: View {
    let project: Project
    @EnvironmentObject var taskRepository: TaskRepository

    var taskCount: Int {
        taskRepository.tasks.filter { $0.projectId == project.id && !$0.isCompleted }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(project.swiftUIColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body)

                if let description = project.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(taskCount)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var taskRepository: TaskRepository
    @State private var showingAddTask = false

    var projectTasks: [OmniTask] {
        taskRepository.tasks
            .filter { $0.projectId == project.id && !$0.isCompleted }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var completedTasks: [OmniTask] {
        taskRepository.tasks
            .filter { $0.projectId == project.id && $0.isCompleted }
            .sorted { ($0.completedAt ?? Date()) > ($1.completedAt ?? Date()) }
    }

    var body: some View {
        List {
            Section {
                ForEach(projectTasks) { task in
                    TaskRowView(task: task)
                }
            } header: {
                Text("Active (\(projectTasks.count))")
            }

            if !completedTasks.isEmpty {
                Section {
                    ForEach(completedTasks.prefix(5)) { task in
                        TaskRowView(task: task)
                    }
                } header: {
                    Text("Completed (\(completedTasks.count))")
                }
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddTask = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        }
        .sheet(isPresented: $showingAddTask) {
            TaskInputSheet(preselectedProject: project)
        }
        .overlay {
            if projectTasks.isEmpty && completedTasks.isEmpty {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: "checklist",
                    description: Text("Add tasks to this project")
                )
            }
        }
    }
}

struct AddProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var projectRepository: ProjectRepository

    @State private var name = ""
    @State private var description = ""
    @State private var selectedColor = "#3B82F6"

    let colors = [
        "#EF4444", "#F97316", "#F59E0B", "#EAB308",
        "#84CC16", "#22C55E", "#10B981", "#14B8A6",
        "#06B6D4", "#0EA5E9", "#3B82F6", "#6366F1",
        "#8B5CF6", "#A855F7", "#D946EF", "#EC4899"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $name)

                    TextField("Description (optional)", text: $description)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if selectedColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                    }
                                }
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createProject()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func createProject() {
        Task {
            let nextSortOrder = (projectRepository.projects.map(\.sortOrder).max() ?? 0) + 1
            let project = Project(
                name: name,
                description: description.isEmpty ? nil : description,
                color: selectedColor,
                sortOrder: nextSortOrder
            )
            try? await projectRepository.create(project)
            dismiss()
        }
    }
}

#Preview {
    ProjectsView()
        .environmentObject(AppEnvironmentiOS())
}
