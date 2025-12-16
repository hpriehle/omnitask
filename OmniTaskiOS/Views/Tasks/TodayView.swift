import SwiftUI
import OmniTaskCore

struct TodayView: View {
    @EnvironmentObject var environment: AppEnvironmentiOS
    @EnvironmentObject var taskRepository: TaskRepository
    @EnvironmentObject var projectRepository: ProjectRepository
    @State private var showingAddTask = false
    @State private var selectedTask: OmniTask?

    var todayTasks: [OmniTask] {
        taskRepository.tasks.filter { task in
            !task.isCompleted && (task.dueDate == nil || Calendar.current.isDateInToday(task.dueDate!))
        }
    }

    var currentTask: OmniTask? {
        taskRepository.tasks.first { $0.isCurrentTask && !$0.isCompleted }
    }

    var body: some View {
        NavigationStack {
            List {
                // Current Task Section
                if let current = currentTask {
                    Section {
                        CurrentTaskCard(
                            task: current,
                            onComplete: {
                                await completeTask(current)
                            },
                            onUnstar: {
                                await unstarTask(current)
                            },
                            onTap: {
                                selectedTask = current
                            }
                        )
                    } header: {
                        Text("Current Focus")
                    }
                }

                // Today's Tasks Section
                Section {
                    if todayTasks.isEmpty {
                        ContentUnavailableView(
                            "No Tasks Today",
                            systemImage: "checkmark.circle",
                            description: Text("Add a task to get started")
                        )
                    } else {
                        ForEach(todayTasks) { task in
                            TaskRowView(task: task)
                        }
                    }
                } header: {
                    Text("Today's Tasks")
                }
            }
            .navigationTitle("Today")
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
                    if environment.cloudKitSyncService.isSyncing {
                        ProgressView()
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                TaskInputSheet()
            }
            .refreshable {
                await environment.cloudKitSyncService.sync()
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Actions

    private func completeTask(_ task: OmniTask) async {
        var updated = task
        updated.isCompleted = true
        updated.completedAt = Date()
        updated.isCurrentTask = false
        try? await taskRepository.update(updated)
    }

    private func unstarTask(_ task: OmniTask) async {
        var updated = task
        updated.isCurrentTask = false
        try? await taskRepository.update(updated)
    }
}

#Preview {
    TodayView()
        .environmentObject(AppEnvironmentiOS())
        .environmentObject(TaskRepository(database: DatabaseManager()))
        .environmentObject(ProjectRepository(database: DatabaseManager()))
}
