import Foundation
import Combine
import AppKit
import SwiftUI
import OmniTaskCore

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
    @Published var scrollToTaskId: String? = nil // Triggers scroll-to-visible in views

    // Pending completion confirmation state (for double-click/double-keypress pattern)
    @Published var pendingCompletionTaskId: String? = nil
    private var pendingCompletionTimer: Task<Void, Never>? = nil
    private let confirmationTimeout: TimeInterval = 2.5 // seconds

    private let taskRepository: TaskRepository
    private let projectRepository: ProjectRepository
    private var cancellables = Set<AnyCancellable>()
    private var skipNextObserverReload = false // Flag to skip reload after optimistic update

    init(taskRepository: TaskRepository, projectRepository: ProjectRepository) {
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository

        // Observe task repository changes
        taskRepository.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Skip reload if we just did an optimistic update
                if self.skipNextObserverReload {
                    print("[TaskListViewModel] Observer: skipping reload (skipNextObserverReload=true)")
                    self.skipNextObserverReload = false
                    return
                }
                print("[TaskListViewModel] Observer: triggering loadTasks()")
                Task { await self.loadTasks() }
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

            withAnimation {
                tasks = fetchedTasks
            }

            // Load subtask counts for all parent tasks
            let parentIds = fetchedTasks.map { $0.id }
            subtaskCounts = try await taskRepository.fetchSubtaskCounts(for: parentIds)
            print("[TaskListViewModel] Loaded subtask counts for \(subtaskCounts.count) tasks")

            // Reload subtasks for expanded tasks
            for taskId in expandedTaskIds {
                await loadSubtasks(for: taskId)
            }

            // Pre-load subtasks for all tasks that have them (for copy functionality)
            for (taskId, counts) in subtaskCounts where counts.total > 0 {
                if subtasks[taskId] == nil {
                    await loadSubtasks(for: taskId)
                }
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
        print("[TaskListViewModel] completeTask called for: '\(task.title)' (id: \(task.id))")
        // Use confirmation flow for tasks with incomplete subtasks
        let result = await attemptCompletion(for: task)
        print("[TaskListViewModel] completeTask - attemptCompletion returned: \(result)")
    }

    func uncompleteTask(_ task: OmniTask) async {
        do {
            try await taskRepository.uncomplete(task)

            // If this is a subtask, update it in the local subtasks array
            if let parentId = task.parentTaskId {
                skipNextObserverReload = true
                if var parentSubtasks = subtasks[parentId],
                   let index = parentSubtasks.firstIndex(where: { $0.id == task.id }) {
                    var updated = parentSubtasks[index]
                    updated.isCompleted = false
                    updated.completedAt = nil
                    parentSubtasks[index] = updated
                    subtasks[parentId] = parentSubtasks
                    print("[TaskListViewModel] uncompleteTask: updated subtask in place at index \(index)")
                }
                // Update subtask counts
                let counts = try await taskRepository.fetchSubtaskCounts(for: [parentId])
                subtaskCounts[parentId] = counts[parentId]
            }
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
        print("[TaskListViewModel] createSubtask called for parent: \(parentId), title: \(title)")

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            print("[TaskListViewModel] createSubtask: empty title, canceling")
            addingSubtaskToTaskId = nil
            return
        }

        // Optimistic update: add subtask locally first to prevent scroll jump
        let optimisticSubtask = OmniTask(
            title: trimmedTitle,
            parentTaskId: parentId
        )
        print("[TaskListViewModel] createSubtask: created optimistic subtask with id: \(optimisticSubtask.id)")

        // Add to local subtasks array
        if subtasks[parentId] != nil {
            subtasks[parentId]?.append(optimisticSubtask)
            print("[TaskListViewModel] createSubtask: appended to existing subtasks array, count now: \(subtasks[parentId]?.count ?? 0)")
        } else {
            subtasks[parentId] = [optimisticSubtask]
            print("[TaskListViewModel] createSubtask: created new subtasks array for parent")
        }

        // Update local subtask count
        if let currentCount = subtaskCounts[parentId] {
            subtaskCounts[parentId] = (total: currentCount.total + 1, completed: currentCount.completed)
            print("[TaskListViewModel] createSubtask: updated subtaskCounts to \(currentCount.total + 1)")
        } else {
            subtaskCounts[parentId] = (total: 1, completed: 0)
            print("[TaskListViewModel] createSubtask: initialized subtaskCounts to 1")
        }

        // Skip the next observer reload since we already updated locally
        skipNextObserverReload = true
        print("[TaskListViewModel] createSubtask: set skipNextObserverReload = true")

        addingSubtaskToTaskId = nil
        print("[TaskListViewModel] createSubtask: cleared addingSubtaskToTaskId")

        do {
            // Create in repository (will trigger observer but we skip the reload)
            print("[TaskListViewModel] createSubtask: calling repository.createSubtask...")
            let createdSubtask = try await taskRepository.createSubtask(parentId: parentId, title: trimmedTitle)
            print("[TaskListViewModel] createSubtask: repository returned subtask with id: \(createdSubtask.id)")

            // Replace optimistic subtask with the real one (has correct ID from DB)
            if var parentSubtasks = subtasks[parentId],
               let index = parentSubtasks.firstIndex(where: { $0.id == optimisticSubtask.id }) {
                parentSubtasks[index] = createdSubtask
                subtasks[parentId] = parentSubtasks
                print("[TaskListViewModel] createSubtask: replaced optimistic subtask with real one at index \(index)")
            } else {
                print("[TaskListViewModel] createSubtask: WARNING - could not find optimistic subtask to replace")
            }
        } catch {
            print("[TaskListViewModel] createSubtask: ERROR - \(error.localizedDescription)")
            // Rollback optimistic update on error
            subtasks[parentId]?.removeAll { $0.id == optimisticSubtask.id }
            if let currentCount = subtaskCounts[parentId], currentCount.total > 0 {
                subtaskCounts[parentId] = (total: currentCount.total - 1, completed: currentCount.completed)
            }
            errorMessage = error.localizedDescription
        }
        print("[TaskListViewModel] createSubtask: completed")
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

    // MARK: - Completion Confirmation Flow

    /// Check if completing a task requires confirmation (has incomplete subtasks)
    func needsCompletionConfirmation(_ taskId: String) -> Bool {
        guard let counts = subtaskCounts[taskId], counts.total > 0 else {
            print("[TaskListViewModel] needsCompletionConfirmation(\(taskId)): NO - no subtasks")
            return false // No subtasks, no confirmation needed
        }
        let needsConfirmation = counts.completed < counts.total
        print("[TaskListViewModel] needsCompletionConfirmation(\(taskId)): \(needsConfirmation) - \(counts.completed)/\(counts.total) completed")
        return needsConfirmation // Has incomplete subtasks
    }

    /// Clear pending completion state
    func clearPendingCompletion() {
        print("[TaskListViewModel] clearPendingCompletion() - was: \(pendingCompletionTaskId ?? "nil")")
        pendingCompletionTimer?.cancel()
        pendingCompletionTimer = nil
        pendingCompletionTaskId = nil
    }

    /// Set pending completion state with timeout
    private func setPendingCompletion(taskId: String) {
        print("[TaskListViewModel] setPendingCompletion(\(taskId)) - starting \(confirmationTimeout)s timeout")
        // Cancel any existing timer
        pendingCompletionTimer?.cancel()

        pendingCompletionTaskId = taskId
        print("[TaskListViewModel] pendingCompletionTaskId set to: \(taskId)")

        // Start timeout timer
        pendingCompletionTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(confirmationTimeout * 1_000_000_000))
            await MainActor.run {
                if self.pendingCompletionTaskId == taskId {
                    print("[TaskListViewModel] Timeout expired - clearing pendingCompletionTaskId")
                    self.pendingCompletionTaskId = nil
                }
            }
        }
    }

    /// Attempt to complete a task with confirmation flow
    /// Returns: true if completed immediately or confirmed, false if pending confirmation
    private func attemptCompletion(for task: OmniTask) async -> Bool {
        print("[TaskListViewModel] attemptCompletion called for task: '\(task.title)' (id: \(task.id))")
        print("[TaskListViewModel] - pendingCompletionTaskId: \(pendingCompletionTaskId ?? "nil")")

        // Check if this task needs confirmation
        if !needsCompletionConfirmation(task.id) {
            print("[TaskListViewModel] No confirmation needed - completing immediately")
            clearPendingCompletion()
            // Complete immediately - optimistically remove from UI first to prevent scroll jump
            removeTaskFromLocalArrays(task.id)
            do {
                try await taskRepository.complete(task)
                print("[TaskListViewModel] Task completed successfully")
                return true
            } catch {
                print("[TaskListViewModel] ERROR completing task: \(error)")
                errorMessage = error.localizedDescription
                // Reload to restore task if completion failed
                await loadTasks()
                return false
            }
        }

        // Check if this is the second click on the same task (confirmation)
        if pendingCompletionTaskId == task.id {
            print("[TaskListViewModel] CONFIRMATION DETECTED - second click on same task")
            clearPendingCompletion()
            // Confirmed - complete with all subtasks - optimistically remove from UI first
            removeTaskFromLocalArrays(task.id)
            do {
                print("[TaskListViewModel] Completing task WITH subtasks...")
                try await taskRepository.completeWithSubtasks(task)
                // Refresh subtask counts since they're now complete
                let counts = try await taskRepository.fetchSubtaskCounts(for: [task.id])
                subtaskCounts[task.id] = counts[task.id]
                print("[TaskListViewModel] Task + subtasks completed successfully")
                return true
            } catch {
                print("[TaskListViewModel] ERROR completing task with subtasks: \(error)")
                errorMessage = error.localizedDescription
                // Reload to restore task if completion failed
                await loadTasks()
                return false
            }
        }

        // First click - set pending state and wait for confirmation
        print("[TaskListViewModel] FIRST CLICK - setting pending state for confirmation")
        setPendingCompletion(taskId: task.id)
        return false
    }

    /// Remove a task from local arrays without triggering full reload
    private func removeTaskFromLocalArrays(_ taskId: String) {
        // Set flag to skip the next observer-triggered reload
        skipNextObserverReload = true
        todayTasksFlat.removeAll { $0.id == taskId }
        overdueTasks.removeAll { $0.id == taskId }
        tasks.removeAll { $0.id == taskId }
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

        // Set flag to skip the next observer-triggered reload
        skipNextObserverReload = true

        // Update subtask in place (don't remove - keep visible with completed state)
        if var parentSubtasks = subtasks[parentId],
           let index = parentSubtasks.firstIndex(where: { $0.id == subtask.id }) {
            var updated = parentSubtasks[index]
            updated.isCompleted = true
            updated.completedAt = Date()
            parentSubtasks[index] = updated
            subtasks[parentId] = parentSubtasks
            print("[TaskListViewModel] completeSubtask: updated subtask in place at index \(index)")
        }

        do {
            try await taskRepository.complete(subtask)
            // Update subtask counts
            let counts = try await taskRepository.fetchSubtaskCounts(for: [parentId])
            subtaskCounts[parentId] = counts[parentId]
        } catch {
            errorMessage = error.localizedDescription
            // Reload subtasks to restore on error
            await loadSubtasks(for: parentId)
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
    /// Returns true if completion was successful, false if validation failed or error occurred
    @discardableResult
    func completeCurrentTask() async -> Bool {
        print("[TaskListViewModel] completeCurrentTask called")
        guard let current = currentTask else {
            print("[TaskListViewModel] ERROR: No current task to complete")
            return false
        }
        print("[TaskListViewModel] Completing task: \(current.title)")

        // Check if this task needs confirmation (has incomplete subtasks)
        if needsCompletionConfirmation(current.id) {
            // Check if this is the second click (confirmation)
            if pendingCompletionTaskId == current.id {
                print("[TaskListViewModel] Second click - confirming completion with subtasks")
                clearPendingCompletion()
                // Continue to complete with subtasks below
            } else {
                // First click - set pending state
                print("[TaskListViewModel] First click - setting pending confirmation")
                setPendingCompletion(taskId: current.id)
                return false
            }
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
            // Complete the task (with subtasks if it has any incomplete ones)
            print("[TaskListViewModel] Completing task in repository...")
            if needsCompletionConfirmation(current.id) || hasSubtasks(current.id) {
                try await taskRepository.completeWithSubtasks(current)
            } else {
                try await taskRepository.complete(current)
            }
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
            return true
        } catch {
            print("[TaskListViewModel] ERROR completing task: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return false
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
            let newTodayTasks = try await taskRepository.fetchTodayTasksFlat()
            let newOverdueTasks = try await taskRepository.fetchOverdueTasksFlat()
            withAnimation {
                todayTasksFlat = newTodayTasks
                overdueTasks = newOverdueTasks
            }
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
    /// This matches the exact order tasks are rendered in the UI
    func getNavigableTaskList() -> [OmniTask] {
        var result: [OmniTask] = []

        if selectedProjectId == nil {
            // Today view - use todayTasksFlat then overdueTasks (matches UI order)
            for task in todayTasksFlat {
                if isCurrentTask(task.id) { continue }
                result.append(task)
                if isExpanded(task.id) {
                    result.append(contentsOf: subtasksFor(task.id))
                }
            }
            // Include overdue tasks (shown in separate section below today tasks)
            for task in overdueTasks {
                if isCurrentTask(task.id) { continue }
                result.append(task)
                if isExpanded(task.id) {
                    result.append(contentsOf: subtasksFor(task.id))
                }
            }
        } else {
            // All view / Project view - use groupedTasks order (sorted by project sortOrder)
            for group in groupedTasks {
                for task in group.tasks {
                    if isCurrentTask(task.id) { continue }
                    result.append(task)
                    if isExpanded(task.id) {
                        result.append(contentsOf: subtasksFor(task.id))
                    }
                }
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
            scrollToTaskId = selectedTaskId
            print("[TaskListViewModel] Selected first task from current task")
            return
        }

        guard let currentId = selectedTaskId,
              let currentIndex = navigable.firstIndex(where: { $0.id == currentId }) else {
            // No selection, select first task
            selectedTaskId = navigable.first?.id
            scrollToTaskId = selectedTaskId
            isCurrentTaskSelected = false
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < navigable.count {
            selectedTaskId = navigable[nextIndex].id
            scrollToTaskId = selectedTaskId
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
            scrollToTaskId = selectedTaskId
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
            // Completing a regular task - use confirmation flow
            let completed = await attemptCompletion(for: task)
            // Only select next task if actually completed (not just pending)
            if completed {
                selectNextTask()
            }
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
