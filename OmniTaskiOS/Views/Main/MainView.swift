import SwiftUI
import OmniTaskCore

/// Main view for the iOS app - single scrollable layout matching macOS design
struct MainView: View {
    @EnvironmentObject var environment: AppEnvironmentiOS
    @EnvironmentObject var taskRepository: TaskRepository
    @EnvironmentObject var projectRepository: ProjectRepository

    @State private var selectedProjectId: String? = nil // nil = Today view
    @State private var showingSettings = false
    @State private var showingTaskDetail: OmniTask?

    // MARK: - Computed Properties

    private var currentTask: OmniTask? {
        taskRepository.tasks.first { $0.isCurrentTask && !$0.isCompleted }
    }

    private var filteredTasks: [OmniTask] {
        let incompleteTasks = taskRepository.tasks.filter { !$0.isCompleted && !$0.isSubtask }

        switch selectedProjectId {
        case nil:
            // Today view: tasks due today or overdue
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

            return incompleteTasks.filter { task in
                guard let dueDate = task.dueDate else { return false }
                return dueDate < tomorrow // Due today or overdue
            }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        case "all":
            // All tasks
            return incompleteTasks.sorted { $0.sortOrder < $1.sortOrder }

        case let projectId?:
            // Specific project
            return incompleteTasks.filter { $0.projectId == projectId }
                .sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    private var headerTitle: String {
        switch selectedProjectId {
        case nil:
            return "Today"
        case "all":
            return "All Tasks"
        case let projectId?:
            return projectRepository.projects.first { $0.id == projectId }?.name ?? "Tasks"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Current Task (sticky below header)
            if let currentTask = currentTask {
                CurrentTaskCard(
                    task: currentTask,
                    onComplete: { await completeTask(currentTask) },
                    onUnstar: { await unstarTask(currentTask) },
                    onTap: { showingTaskDetail = currentTask }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // Projects bar
            ProjectTabsView(
                projects: projectRepository.projects,
                selectedProjectId: $selectedProjectId
            )

            // Task list
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filteredTasks.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(filteredTasks) { task in
                            TaskRowView(task: task)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // Task input bar (fixed at bottom)
            TaskInputBar()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(item: $showingTaskDetail) { task in
            TaskDetailView(task: task)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Text(headerTitle)
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            // Sync status indicator
            if environment.cloudKitSyncService.isSyncing {
                ProgressView()
                    .scaleEffect(0.8)
            }

            // Settings button
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(selectedProjectId == nil ? "No Tasks Today" : "No Tasks")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add a task to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
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
    MainView()
        .environmentObject(AppEnvironmentiOS())
}
