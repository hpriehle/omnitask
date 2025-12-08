import Foundation
import Combine
import AppKit

/// ViewModel for the task list
@MainActor
final class TaskListViewModel: ObservableObject {
    @Published var tasks: [OmniTask] = []
    @Published var selectedProjectId: String? // nil = Today view
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var todayCount: Int = 0 // Always tracks Today tasks regardless of selected view

    // Current task state
    @Published var currentTask: OmniTask?
    @Published var todayTasksFlat: [OmniTask] = [] // Flat list for Today tab (excluding current task)
    @Published var overdueTasks: [OmniTask] = [] // Overdue tasks for Today tab (shown in separate section)
    @Published var isOverdueSectionCollapsed: Bool = false // Collapse state for overdue section

    // Completed tasks (shown in separate section when showCompleted is enabled)
    @Published var completedTasks: [OmniTask] = []

    // Filter settings reference (set by caller, typically from AppEnvironment)
    var filterSettings: FilterSortSettings = .default

    // Subtask state
    @Published var expandedTaskIds: Set<String> = []
    @Published var subtaskCounts: [String: (total: Int, completed: Int)] = [:]
    @Published var subtasks: [String: [OmniTask]] = [:] // parentId -> subtasks
    @Published var addingSubtaskToTaskId: String? = nil

    // Keyboard navigation state
    // nil = current task in footer selected, "first" marker handled specially
    @Published var selectedTaskId: String? = nil
    @Published var isCurrentTaskSelected: Bool = true // Start with current task selected

    private let taskRepository: TaskRepository
    private let projectRepository: ProjectRepository
    private var cancellables = Set<AnyCancellable>()

    init(taskRepository: TaskRepository, projectRepository: ProjectRepository) {
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository

        // Observe task repository changes
        taskRepository.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.loadTasks() }
            }
            .store(in: &cancellables)

        // Load tasks and current task immediately on init
        Task {
            await loadCurrentTask()
            await loadTasks()
        }
    }

    // MARK: - Loading

    func loadTasks() async {
        print("[TaskListViewModel] loadTasks called, selectedProjectId: \(selectedProjectId ?? "nil (Today)")")
        isLoading = true
        errorMessage = nil

        do {
            var fetchedTasks: [OmniTask] = []
            let isTodayView = selectedProjectId == nil

            if selectedProjectId == "all" {
                // All tasks view - grouped by project (top-level only)
                print("[TaskListViewModel] Fetching all top-level tasks...")
                let rawTasks = try await taskRepository.fetchTopLevelTasks(includeCompleted: false)
                // Apply filters and sorting (due date filter applies here)
                fetchedTasks = applyFiltersAndSort(rawTasks, isTodayView: false)
                print("[TaskListViewModel] Fetched \(rawTasks.count) tasks, after filters: \(fetchedTasks.count) for All view")
            } else if let projectId = selectedProjectId {
                // Project-specific view (top-level only)
                print("[TaskListViewModel] Fetching tasks for project: \(projectId)")
                let projectTasks = try await taskRepository.fetchByProject(projectId)
                let topLevel = projectTasks.filter { $0.parentTaskId == nil }
                // Apply filters and sorting (due date filter applies here)
                fetchedTasks = applyFiltersAndSort(topLevel, isTodayView: false)
                print("[TaskListViewModel] Fetched \(topLevel.count) tasks, after filters: \(fetchedTasks.count) for project")
            } else {
                // Today view: overdue + due today (top-level only)
                // Due date filter is IGNORED for Today view - always shows overdue+today
                print("[TaskListViewModel] Fetching Today tasks (overdue + today)...")
                let overdue = try await taskRepository.fetchOverdueTasks()
                let today = try await taskRepository.fetchTodayTasks()
                print("[TaskListViewModel] Fetched \(overdue.count) overdue, \(today.count) today tasks")

                // Combine and deduplicate, filter to top-level only
                var allTasks = overdue.filter { $0.parentTaskId == nil }
                for task in today where !allTasks.contains(where: { $0.id == task.id }) && task.parentTaskId == nil {
                    allTasks.append(task)
                }

                // Apply filters and sorting (isTodayView=true skips due date filter)
                fetchedTasks = applyFiltersAndSort(allTasks, isTodayView: true)
                print("[TaskListViewModel] After filters & sort, Today tasks count: \(fetchedTasks.count)")
            }

            tasks = fetchedTasks

            // Load subtask counts for all parent tasks
            let parentIds = fetchedTasks.map { $0.id }
            subtaskCounts = try await taskRepository.fetchSubtaskCounts(for: parentIds)
            print("[TaskListViewModel] Loaded subtask counts for \(subtaskCounts.count) tasks")

            // Reload subtasks for expanded tasks
            for taskId in expandedTaskIds {
                await loadSubtasks(for: taskId)
            }

            // Load completed tasks if showCompleted is enabled
            await loadCompletedTasks()

            // Always update Today count regardless of current view
            await refreshTodayCount()

            // Refresh today tasks flat list when viewing Today tab
            if isTodayView {
                await loadTodayTasksFlat()
            }
        } catch {
            print("[TaskListViewModel] ERROR loading tasks: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
        print("[TaskListViewModel] loadTasks finished, isLoading = false")
    }

    // MARK: - Actions

    func completeTask(_ task: OmniTask) async {
        // Prevent completing parent tasks with incomplete subtasks
        if !canCompleteParent(task.id) {
            errorMessage = "Complete all subtasks first"
            return
        }

        do {
            try await taskRepository.complete(task)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uncompleteTask(_ task: OmniTask) async {
        do {
            try await taskRepository.uncomplete(task)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTask(_ task: OmniTask) async {
        do {
            try await taskRepository.delete(task)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTask(_ task: OmniTask) async {
        print("[TaskListViewModel] updateTask called for: \(task.title)")
        print("[TaskListViewModel] Task ID: \(task.id)")
        do {
            print("[TaskListViewModel] Calling taskRepository.update...")
            try await taskRepository.update(task)
            print("[TaskListViewModel] Repository update complete, now calling loadTasks...")
            await loadTasks()
            print("[TaskListViewModel] loadTasks complete, task count: \(tasks.count)")
        } catch {
            print("[TaskListViewModel] ERROR updating task: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func moveTask(from source: IndexSet, to destination: Int) async {
        var reorderedTasks = tasks
        reorderedTasks.move(fromOffsets: source, toOffset: destination)

        // Update sort orders
        for (index, task) in reorderedTasks.enumerated() {
            do {
                try await taskRepository.updateSortOrder(taskId: task.id, newOrder: index)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        tasks = reorderedTasks
    }

    func selectProject(_ projectId: String?) {
        selectedProjectId = projectId
        Task { await loadTasks() }
    }

    // MARK: - Quick Date Actions

    /// Set task due date to today (11:59 PM)
    func setDueToday(_ task: OmniTask) async {
        var updated = task
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(23 * 3600 + 59 * 60)
        updated.dueDate = endOfToday
        await updateTask(updated)
    }

    /// Defer task by 24 hours
    func deferBy24Hours(_ task: OmniTask) async {
        var updated = task
        if let currentDue = task.dueDate {
            updated.dueDate = currentDue.addingTimeInterval(24 * 3600)
        } else {
            // If no due date, set to tomorrow 11:59 PM
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            updated.dueDate = Calendar.current.startOfDay(for: tomorrow).addingTimeInterval(23 * 3600 + 59 * 60)
        }
        await updateTask(updated)
    }

    // MARK: - Filter & Sort Helpers

    /// Apply priority filter to tasks
    private func applyPriorityFilter(_ tasks: [OmniTask]) -> [OmniTask] {
        // If all priorities are selected, no filtering needed
        if filterSettings.selectedPriorities == Set(Priority.allCases) {
            return tasks
        }
        return tasks.filter { filterSettings.selectedPriorities.contains($0.priority) }
    }

    /// Apply due date filter to tasks (NOT applied to Today view)
    private func applyDueDateFilter(_ tasks: [OmniTask]) -> [OmniTask] {
        guard filterSettings.dueDateFilter != .all else { return tasks }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        return tasks.filter { task in
            switch filterSettings.dueDateFilter {
            case .all:
                return true
            case .overdue:
                guard let dueDate = task.dueDate else { return false }
                return dueDate < now && !task.isCompleted
            case .today:
                guard let dueDate = task.dueDate else { return false }
                return dueDate >= startOfToday && dueDate < endOfToday
            case .thisWeek:
                guard let dueDate = task.dueDate else { return false }
                let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday)!
                return dueDate >= startOfToday && dueDate < endOfWeek
            case .thisMonth:
                guard let dueDate = task.dueDate else { return false }
                let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfToday)!
                return dueDate >= startOfToday && dueDate < endOfMonth
            case .noDueDate:
                return task.dueDate == nil
            }
        }
    }

    /// Sort tasks according to current sort option
    private func applySorting(_ tasks: [OmniTask]) -> [OmniTask] {
        return tasks.sorted { task1, task2 in
            switch filterSettings.sortOption {
            case .dueDateAsc:
                // Tasks with due dates first, then by date ascending
                if let d1 = task1.dueDate, let d2 = task2.dueDate {
                    return d1 < d2
                }
                return task1.dueDate != nil && task2.dueDate == nil
            case .dueDateDesc:
                if let d1 = task1.dueDate, let d2 = task2.dueDate {
                    return d1 > d2
                }
                return task1.dueDate != nil && task2.dueDate == nil
            case .priorityAsc:
                // Higher priority (lower raw value) first
                return task1.priority < task2.priority
            case .priorityDesc:
                return task1.priority > task2.priority
            case .titleAsc:
                return task1.title.localizedCaseInsensitiveCompare(task2.title) == .orderedAscending
            case .titleDesc:
                return task1.title.localizedCaseInsensitiveCompare(task2.title) == .orderedDescending
            case .createdAsc:
                return task1.createdAt < task2.createdAt
            case .createdDesc:
                return task1.createdAt > task2.createdAt
            }
        }
    }

    /// Apply all filters and sorting to a task list
    /// - Parameter tasks: The raw tasks to filter/sort
    /// - Parameter isTodayView: If true, skip due date filter (Today view has its own logic)
    private func applyFiltersAndSort(_ tasks: [OmniTask], isTodayView: Bool = false) -> [OmniTask] {
        var result = tasks

        // Apply priority filter
        result = applyPriorityFilter(result)

        // Apply due date filter (skip for Today view)
        if !isTodayView {
            result = applyDueDateFilter(result)
        }

        // Apply sorting
        result = applySorting(result)

        return result
    }

    /// Load completed tasks for the current view (not shown in Today view)
    private func loadCompletedTasks() async {
        // Don't show completed tasks in Today view
        guard filterSettings.showCompleted, selectedProjectId != nil else {
            completedTasks = []
            return
        }

        do {
            var completed: [OmniTask] = []

            if selectedProjectId == "all" {
                // All view - all completed top-level tasks
                let allCompleted = try await taskRepository.fetchCompletedTasks(limit: 100)
                completed = allCompleted.filter { $0.parentTaskId == nil }
            } else if let projectId = selectedProjectId {
                // Project view - completed tasks for this project
                let projectTasks = try await taskRepository.fetchByProject(projectId, includeCompleted: true)
                completed = projectTasks.filter { $0.isCompleted && $0.parentTaskId == nil }
            }

            // Apply priority filter to completed tasks too
            completed = applyPriorityFilter(completed)

            // Sort completed by completion date (most recent first)
            completedTasks = completed.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

            print("[TaskListViewModel] Loaded \(completedTasks.count) completed tasks")
        } catch {
            print("[TaskListViewModel] Error loading completed tasks: \(error)")
            completedTasks = []
        }
    }

    // MARK: - Helpers

    var groupedTasks: [(project: Project?, tasks: [OmniTask])] {
        guard selectedProjectId == nil || selectedProjectId == "all" else {
            // Single project view - no grouping
            return [(nil, tasks)]
        }

        // Group by project for Today and All views
        var groups: [String?: [OmniTask]] = [:]

        for task in tasks {
            groups[task.projectId, default: []].append(task)
        }

        return groups.map { projectId, tasks in
            let project = projectRepository.projects.first { $0.id == projectId }
            return (project, tasks)
        }.sorted { group1, group2 in
            let order1 = group1.project?.sortOrder ?? 999
            let order2 = group2.project?.sortOrder ?? 999
            return order1 < order2
        }
    }

    var todayTaskCount: Int {
        // Return the always-current Today count (today tasks only, not overdue)
        todayCount
    }

    /// Refresh the Today task count (called on every loadTasks)
    /// This count ONLY includes tasks due today (NOT overdue) since overdue is shown in a separate section
    /// This count excludes the current task since it's shown separately in the footer
    /// Priority filter is applied to match what's displayed in the Today view
    private func refreshTodayCount() async {
        do {
            // Only count tasks due TODAY, not overdue (overdue shown in separate section)
            let today = try await taskRepository.fetchTodayTasks()
            let currentTaskId = currentTask?.id

            print("[TaskListViewModel] refreshTodayCount - today tasks only: \(today.count)")
            for task in today {
                print("  - Today: '\(task.title)' (id: \(task.id), parentId: \(task.parentTaskId ?? "nil"), isCompleted: \(task.isCompleted), priority: \(task.priority))")
            }

            // Apply same priority filter as the display uses
            let filteredPriorities = filterSettings.selectedPriorities
            let hasActivePriorityFilter = filteredPriorities != Set(Priority.allCases)
            print("[TaskListViewModel] Priority filter active: \(hasActivePriorityFilter), selected: \(filteredPriorities)")

            // Count only top-level incomplete tasks due TODAY, excluding current task
            var count = 0
            print("[TaskListViewModel] Processing today tasks for count...")
            for task in today where task.parentTaskId == nil && !task.isCompleted {
                // Skip current task - it's shown separately in footer
                if task.id == currentTaskId {
                    print("  - SKIP (is current task): '\(task.title)'")
                    continue
                }
                // Apply priority filter
                if hasActivePriorityFilter && !filteredPriorities.contains(task.priority) {
                    print("  - SKIP (priority filtered): '\(task.title)' priority=\(task.priority)")
                    continue
                }
                count += 1
                print("  - COUNTED (today): '\(task.title)' -> count=\(count)")
            }
            todayCount = count
            print("[TaskListViewModel] *** refreshTodayCount FINAL: \(count) (today only, no overdue) *** (currentTaskId: \(currentTaskId ?? "nil"))")
        } catch {
            print("[TaskListViewModel] Error refreshing today count: \(error)")
        }
    }

    // MARK: - Subtask Management

    /// Load subtasks for a specific parent task
    func loadSubtasks(for parentId: String) async {
        do {
            let taskSubtasks = try await taskRepository.fetchSubtasks(for: parentId)
            subtasks[parentId] = taskSubtasks
            print("[TaskListViewModel] Loaded \(taskSubtasks.count) subtasks for parent: \(parentId)")
        } catch {
            print("[TaskListViewModel] Error loading subtasks: \(error)")
        }
    }

    /// Toggle expansion state for a task
    func toggleExpanded(_ taskId: String) async {
        if expandedTaskIds.contains(taskId) {
            expandedTaskIds.remove(taskId)
        } else {
            expandedTaskIds.insert(taskId)
            // Load subtasks if not already loaded
            if subtasks[taskId] == nil {
                await loadSubtasks(for: taskId)
            }
        }
    }

    /// Check if a task is expanded
    func isExpanded(_ taskId: String) -> Bool {
        expandedTaskIds.contains(taskId)
    }

    /// Get subtasks for a parent task
    func subtasksFor(_ parentId: String) -> [OmniTask] {
        subtasks[parentId] ?? []
    }

    /// Get subtask count info for a task
    func subtaskCountFor(_ taskId: String) -> (total: Int, completed: Int)? {
        subtaskCounts[taskId]
    }

    /// Check if task has subtasks
    func hasSubtasks(_ taskId: String) -> Bool {
        if let counts = subtaskCounts[taskId] {
            return counts.total > 0
        }
        return false
    }

    /// Start adding a subtask to a parent
    func startAddingSubtask(to parentId: String) {
        addingSubtaskToTaskId = parentId
        // Ensure the task is expanded
        if !expandedTaskIds.contains(parentId) {
            Task { await toggleExpanded(parentId) }
        }
    }

    /// Cancel adding a subtask
    func cancelAddingSubtask() {
        addingSubtaskToTaskId = nil
    }

    /// Create a new subtask
    func createSubtask(parentId: String, title: String) async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            addingSubtaskToTaskId = nil
            return
        }

        do {
            _ = try await taskRepository.createSubtask(parentId: parentId, title: title)
            addingSubtaskToTaskId = nil
            // Reload subtasks for this parent
            await loadSubtasks(for: parentId)
            // Update subtask counts
            let counts = try await taskRepository.fetchSubtaskCounts(for: [parentId])
            if let count = counts[parentId] {
                subtaskCounts[parentId] = count
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Check if currently adding subtask to a specific task
    func isAddingSubtask(to taskId: String) -> Bool {
        addingSubtaskToTaskId == taskId
    }

    /// Check if a parent task can be completed (all subtasks must be done)
    func canCompleteParent(_ taskId: String) -> Bool {
        guard let counts = subtaskCounts[taskId] else {
            return true // No subtasks, can complete
        }
        return counts.completed == counts.total
    }

    /// Delete a subtask
    func deleteSubtask(_ subtask: OmniTask) async {
        guard let parentId = subtask.parentTaskId else { return }

        do {
            try await taskRepository.delete(subtask)
            // Reload subtasks for this parent
            await loadSubtasks(for: parentId)
            // Update subtask counts
            let counts = try await taskRepository.fetchSubtaskCounts(for: [parentId])
            subtaskCounts[parentId] = counts[parentId]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Complete a subtask
    func completeSubtask(_ subtask: OmniTask) async {
        guard let parentId = subtask.parentTaskId else { return }

        do {
            try await taskRepository.complete(subtask)
            // Reload subtasks for this parent
            await loadSubtasks(for: parentId)
            // Update subtask counts
            let counts = try await taskRepository.fetchSubtaskCounts(for: [parentId])
            subtaskCounts[parentId] = counts[parentId]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Uncomplete a subtask
    func uncompleteSubtask(_ subtask: OmniTask) async {
        guard let parentId = subtask.parentTaskId else { return }

        do {
            try await taskRepository.uncomplete(subtask)
            // Reload subtasks for this parent
            await loadSubtasks(for: parentId)
            // Update subtask counts
            let counts = try await taskRepository.fetchSubtaskCounts(for: [parentId])
            subtaskCounts[parentId] = counts[parentId]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Current Task

    /// Load the current task from the database
    func loadCurrentTask() async {
        do {
            currentTask = try await taskRepository.fetchCurrentTask()
            print("[TaskListViewModel] Loaded current task: \(currentTask?.title ?? "none")")
        } catch {
            print("[TaskListViewModel] Error loading current task: \(error)")
        }
    }

    /// Set a task as the current task
    func setCurrentTask(_ task: OmniTask) async {
        do {
            try await taskRepository.setCurrentTask(task.id)
            currentTask = task
            // Reload today tasks to exclude the new current task
            await loadTodayTasksFlat()
            print("[TaskListViewModel] Set current task: \(task.title)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clear the current task (no task is current)
    func clearCurrentTask() async {
        do {
            try await taskRepository.clearCurrentTask()
            currentTask = nil
            await loadTodayTasksFlat()
            print("[TaskListViewModel] Cleared current task")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Complete the current task and auto-advance to the next one
    func completeCurrentTask() async {
        print("[TaskListViewModel] completeCurrentTask called")
        guard let current = currentTask else {
            print("[TaskListViewModel] ERROR: No current task to complete")
            return
        }
        print("[TaskListViewModel] Completing task: \(current.title)")

        // Prevent completing if subtasks are incomplete
        if !canCompleteParent(current.id) {
            print("[TaskListViewModel] ERROR: Cannot complete - subtasks incomplete")
            errorMessage = "Complete all subtasks first"
            return
        }

        // Trigger confetti + sound
        print("[TaskListViewModel] Attempting to trigger confetti and sound...")
        if let windowManager = WindowManager.shared {
            let position = windowManager.collapsedPillCenter
            print("[TaskListViewModel] Confetti position: \(position)")
            NotificationCenter.default.post(name: .triggerConfetti, object: nil, userInfo: ["position": position])
            print("[TaskListViewModel] Posted triggerConfetti notification")

            if let sound = NSSound(named: "Ping") {
                sound.play()
                print("[TaskListViewModel] Playing sound: Ping")
            } else {
                print("[TaskListViewModel] WARNING: Sound 'Ping' not found, trying Glass")
                NSSound(named: "Glass")?.play()
            }
        } else {
            print("[TaskListViewModel] ERROR: WindowManager.shared is nil")
        }

        // Wait for confetti animation before advancing
        print("[TaskListViewModel] Waiting 1.5s for confetti animation...")
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        print("[TaskListViewModel] Confetti delay complete, proceeding with task completion")

        do {
            // Complete the task
            print("[TaskListViewModel] Completing task in repository...")
            try await taskRepository.complete(current)
            print("[TaskListViewModel] Task completed in repository")

            // Get the next task in today's list
            let todayTasks = try await taskRepository.fetchTodayTasksFlat()
            print("[TaskListViewModel] Fetched \(todayTasks.count) remaining today tasks")
            if let nextTask = todayTasks.first {
                // Set the next task as current
                try await taskRepository.setCurrentTask(nextTask.id)
                currentTask = nextTask
                print("[TaskListViewModel] Auto-advanced to next task: \(nextTask.title)")
            } else {
                // No more tasks - clear current
                currentTask = nil
                print("[TaskListViewModel] No more tasks in Today, cleared current")
            }

            // Reload today tasks
            await loadTodayTasksFlat()
            await refreshTodayCount()
            print("[TaskListViewModel] completeCurrentTask finished successfully")
        } catch {
            print("[TaskListViewModel] ERROR completing task: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Check if a task is the current task
    func isCurrentTask(_ taskId: String) -> Bool {
        currentTask?.id == taskId
    }

    // MARK: - Today Tab Flat Ordering

    /// Load today's tasks as a flat, reorderable list (excluding current task)
    /// Also loads overdue tasks separately for the overdue section
    func loadTodayTasksFlat() async {
        do {
            todayTasksFlat = try await taskRepository.fetchTodayTasksFlat()
            overdueTasks = try await taskRepository.fetchOverdueTasksFlat()
            print("[TaskListViewModel] Loaded \(todayTasksFlat.count) today tasks, \(overdueTasks.count) overdue tasks (flat)")
        } catch {
            print("[TaskListViewModel] Error loading today tasks flat: \(error)")
        }
    }

    /// Reorder tasks in the Today tab
    func reorderTodayTasks(from source: IndexSet, to destination: Int) async {
        var reordered = todayTasksFlat
        reordered.move(fromOffsets: source, toOffset: destination)

        // Update sort orders in database
        let orderings = reordered.enumerated().map { (index, task) in
            (taskId: task.id, order: index)
        }

        do {
            try await taskRepository.updateTodaySortOrders(orderings)
            todayTasksFlat = reordered
            print("[TaskListViewModel] Reordered today tasks")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Keyboard Navigation

    /// Get a flat list of all navigable tasks (including expanded subtasks)
    func getNavigableTaskList() -> [OmniTask] {
        var result: [OmniTask] = []

        // Use todayTasksFlat for Today view, tasks for other views
        let taskList = selectedProjectId == nil ? todayTasksFlat : tasks

        for task in taskList {
            // Skip current task (it's in footer)
            if isCurrentTask(task.id) { continue }

            result.append(task)

            // If expanded, add subtasks
            if isExpanded(task.id) {
                let taskSubtasks = subtasksFor(task.id)
                result.append(contentsOf: taskSubtasks)
            }
        }

        return result
    }

    /// Select the next task in the navigation order
    func selectNextTask() {
        let navigable = getNavigableTaskList()
        guard !navigable.isEmpty else { return }

        if isCurrentTaskSelected {
            // Moving from current task footer to first task in list
            isCurrentTaskSelected = false
            selectedTaskId = navigable.first?.id
            print("[TaskListViewModel] Selected first task from current task")
            return
        }

        guard let currentId = selectedTaskId,
              let currentIndex = navigable.firstIndex(where: { $0.id == currentId }) else {
            // No selection, select first task
            selectedTaskId = navigable.first?.id
            isCurrentTaskSelected = false
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < navigable.count {
            selectedTaskId = navigable[nextIndex].id
            print("[TaskListViewModel] Selected next task at index \(nextIndex)")
        }
        // At end of list, don't wrap
    }

    /// Select the previous task in the navigation order
    func selectPreviousTask() {
        let navigable = getNavigableTaskList()

        if isCurrentTaskSelected {
            // Already at current task (top of navigation), do nothing
            return
        }

        guard let currentId = selectedTaskId,
              let currentIndex = navigable.firstIndex(where: { $0.id == currentId }) else {
            // No selection, go to current task
            selectCurrentTaskInFooter()
            return
        }

        if currentIndex == 0 {
            // At first task, go back to current task in footer
            selectCurrentTaskInFooter()
            print("[TaskListViewModel] Selected current task in footer from first task")
        } else {
            selectedTaskId = navigable[currentIndex - 1].id
            print("[TaskListViewModel] Selected previous task at index \(currentIndex - 1)")
        }
    }

    /// Select the current task in footer
    func selectCurrentTaskInFooter() {
        selectedTaskId = nil
        isCurrentTaskSelected = true
        print("[TaskListViewModel] Selected current task in footer")
    }

    /// Clear keyboard selection
    func clearSelection() {
        selectedTaskId = nil
        isCurrentTaskSelected = currentTask != nil
        print("[TaskListViewModel] Cleared selection, isCurrentTaskSelected: \(isCurrentTaskSelected)")
    }

    /// Get the currently selected task (either from list or current task)
    func getSelectedTask() -> OmniTask? {
        if isCurrentTaskSelected {
            return currentTask
        }
        if let id = selectedTaskId {
            // Check in navigable list
            return getNavigableTaskList().first { $0.id == id }
        }
        return nil
    }

    /// Complete the currently selected task
    func completeSelectedTask() async {
        guard let task = getSelectedTask() else { return }

        if isCurrentTaskSelected {
            // Completing current task - use existing method which auto-advances
            await completeCurrentTask()
        } else if task.isSubtask {
            // Completing a subtask
            await completeSubtask(task)
            // Select next task after completion
            selectNextTask()
        } else {
            // Completing a regular task
            await completeTask(task)
            // Select next task after completion
            selectNextTask()
        }
    }

    /// Toggle the selected task as current task
    func toggleSelectedAsCurrent() async {
        guard let task = getSelectedTask() else { return }

        // Don't allow setting subtasks as current
        if task.isSubtask { return }

        if isCurrentTask(task.id) {
            // Already current, clear it
            await clearCurrentTask()
        } else {
            // Set as current
            await setCurrentTask(task)
            // Move selection to footer
            selectCurrentTaskInFooter()
        }
    }

    /// Start adding subtask to the selected task
    func addSubtaskToSelected() {
        guard let task = getSelectedTask() else { return }

        // Can only add subtasks to parent tasks, not to subtasks
        if task.isSubtask { return }

        startAddingSubtask(to: task.id)
    }
}
