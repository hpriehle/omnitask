import SwiftUI
import OmniTaskCore

struct AllTasksView: View {
    @EnvironmentObject var environment: AppEnvironmentiOS
    @EnvironmentObject var taskRepository: TaskRepository
    @EnvironmentObject var projectRepository: ProjectRepository
    @State private var showingAddTask = false
    @State private var selectedProject: Project?
    @State private var searchText = ""

    var filteredTasks: [OmniTask] {
        var tasks = taskRepository.tasks.filter { !$0.isCompleted }

        if let project = selectedProject {
            tasks = tasks.filter { $0.projectId == project.id }
        }

        if !searchText.isEmpty {
            tasks = tasks.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return tasks.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredTasks) { task in
                    TaskRowView(task: task)
                }
            }
            .navigationTitle("All Tasks")
            .searchable(text: $searchText, prompt: "Search tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddTask = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("All Projects") {
                            selectedProject = nil
                        }
                        Divider()
                        ForEach(projectRepository.projects) { project in
                            Button(project.name) {
                                selectedProject = project
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            if let project = selectedProject {
                                Text(project.name)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                TaskInputSheet()
            }
            .overlay {
                if filteredTasks.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Tasks" : "No Results",
                        systemImage: searchText.isEmpty ? "checklist" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Add a task to get started" : "Try a different search")
                    )
                }
            }
        }
    }
}

#Preview {
    AllTasksView()
        .environmentObject(AppEnvironmentiOS())
}
