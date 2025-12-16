import Foundation
import GRDB

/// Repository for Task CRUD operations
@MainActor
public final class TaskRepository: ObservableObject {
    private let database: DatabaseManager
    @Published public private(set) var tasks: [OmniTask] = []

    public init(database: DatabaseManager) {
        self.database = database
        loadTasks()
    }

    private func loadTasks() {
        do {
            tasks = try database.read { db in
                try OmniTask
                    .filter(Column("isCompleted") == false)
                    .order(Column("sortOrder").asc, Column("createdAt").desc)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }

    // MARK: - Create

    public func create(_ task: OmniTask) async throws {
        print("[TaskRepository] Creating task: \"\(task.title)\"")
        print("  - Project ID: \(task.projectId ?? "none")")
        print("  - Priority: \(task.priority.displayName)")
        print("  - Due date: \(task.dueDate?.description ?? "none")")

        try await database.asyncWrite { db in
            var task = task
            try task.insert(db)
        }
        print("[TaskRepository] Task created successfully!")
        loadTasks()
    }

    public func createMultiple(_ tasks: [OmniTask]) async throws {
        print("[TaskRepository] Creating \(tasks.count) task(s)...")
        for task in tasks {
            print("  - \"\(task.title)\" (priority: \(task.priority.displayName), project: \(task.projectId ?? "none"))")
        }

        try await database.asyncWrite { db in
            for var task in tasks {
                try task.insert(db)
            }
        }
        print("[TaskRepository] All tasks created successfully!")
        loadTasks()
    }

    // MARK: - Read

    public func fetchAll(includeCompleted: Bool = false) async throws -> [OmniTask] {
        try await database.asyncRead { db in
            var request = OmniTask.all()
            if !includeCompleted {
                request = request.filter(Column("isCompleted") == false)
            }
            return try request.order(Column("sortOrder").asc).fetchAll(db)
        }
    }

    public func fetchByProject(_ projectId: String?, includeCompleted: Bool = false) async throws -> [OmniTask] {
        try await database.asyncRead { db in
            var request: QueryInterfaceRequest<OmniTask>
            if let projectId = projectId {
                request = OmniTask.filter(Column("projectId") == projectId)
            } else {
                request = OmniTask.filter(Column("projectId") == nil)
            }
            if !includeCompleted {
                request = request.filter(Column("isCompleted") == false)
            }
            return try request.order(Column("sortOrder").asc).fetchAll(db)
        }
    }

    public func fetchTodayTasks() async throws -> [OmniTask] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await database.asyncRead { db in
            try OmniTask
                .filter(Column("isCompleted") == false)
                .filter(Column("dueDate") >= startOfDay && Column("dueDate") < endOfDay)
                .order(Column("dueDate").asc, Column("priority").desc)
                .fetchAll(db)
        }
    }

    public func fetchOverdueTasks() async throws -> [OmniTask] {
        let now = Date()
        return try await database.asyncRead { db in
            try OmniTask
                .filter(Column("isCompleted") == false)
                .filter(Column("dueDate") != nil && Column("dueDate") < now)
                .order(Column("dueDate").asc)
                .fetchAll(db)
        }
    }

    public func fetchSubtasks(for parentId: String) async throws -> [OmniTask] {
        try await database.asyncRead { db in
            try OmniTask
                .filter(Column("parentTaskId") == parentId)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
        }
    }

    /// Fetch subtask counts for multiple parent tasks
    public func fetchSubtaskCounts(for parentIds: [String]) async throws -> [String: (total: Int, completed: Int)] {
        guard !parentIds.isEmpty else { return [:] }

        return try await database.asyncRead { db in
            var result: [String: (total: Int, completed: Int)] = [:]

            for parentId in parentIds {
                let total = try OmniTask
                    .filter(Column("parentTaskId") == parentId)
                    .fetchCount(db)

                let completed = try OmniTask
                    .filter(Column("parentTaskId") == parentId)
                    .filter(Column("isCompleted") == true)
                    .fetchCount(db)

                if total > 0 {
                    result[parentId] = (total, completed)
                }
            }

            return result
        }
    }

    /// Create a subtask for a parent task
    public func createSubtask(parentId: String, title: String) async throws -> OmniTask {
        // Get parent task to inherit properties
        let parent = try await database.asyncRead { db in
            try OmniTask.fetchOne(db, key: parentId)
        }

        // Get current subtask count for sort order
        let existingCount = try await database.asyncRead { db in
            try OmniTask
                .filter(Column("parentTaskId") == parentId)
                .fetchCount(db)
        }

        let subtask = OmniTask(
            title: title,
            parentTaskId: parentId,
            priority: parent?.priority ?? .medium,
            dueDate: parent?.dueDate,
            sortOrder: existingCount
        )

        try await create(subtask)
        return subtask
    }

    /// Check if all subtasks of a parent are completed
    public func areAllSubtasksCompleted(parentId: String) async throws -> Bool {
        let counts = try await fetchSubtaskCounts(for: [parentId])
        guard let subtaskInfo = counts[parentId] else {
            return true // No subtasks means "all done"
        }
        return subtaskInfo.completed == subtaskInfo.total
    }

    /// Fetch top-level tasks only (no subtasks)
    public func fetchTopLevelTasks(includeCompleted: Bool = false) async throws -> [OmniTask] {
        try await database.asyncRead { db in
            var request = OmniTask
                .filter(Column("parentTaskId") == nil)

            if !includeCompleted {
                request = request.filter(Column("isCompleted") == false)
            }

            return try request.order(Column("sortOrder").asc, Column("createdAt").desc).fetchAll(db)
        }
    }

    /// Fetch today's tasks including subtasks whose parent is due today
    public func fetchTodayTasksWithSubtasks() async throws -> [OmniTask] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await database.asyncRead { db in
            // Get IDs of parent tasks due today
            let todayParentIds = try OmniTask
                .filter(Column("isCompleted") == false)
                .filter(Column("parentTaskId") == nil)
                .filter(Column("dueDate") >= startOfDay && Column("dueDate") < endOfDay)
                .select(Column("id"))
                .asRequest(of: String.self)
                .fetchAll(db)

            // Fetch today's parent tasks
            let parentTasks = try OmniTask
                .filter(Column("isCompleted") == false)
                .filter(Column("parentTaskId") == nil)
                .filter(Column("dueDate") >= startOfDay && Column("dueDate") < endOfDay)
                .order(Column("dueDate").asc, Column("priority").desc)
                .fetchAll(db)

            // Fetch subtasks for those parents (regardless of their own due date)
            let subtasks: [OmniTask]
            if !todayParentIds.isEmpty {
                subtasks = try OmniTask
                    .filter(todayParentIds.contains(Column("parentTaskId")))
                    .filter(Column("isCompleted") == false)
                    .order(Column("sortOrder").asc)
                    .fetchAll(db)
            } else {
                subtasks = []
            }

            return parentTasks + subtasks
        }
    }

    public func fetchCompletedTasks(limit: Int = 100) async throws -> [OmniTask] {
        try await database.asyncRead { db in
            try OmniTask
                .filter(Column("isCompleted") == true)
                .order(Column("completedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Update

    public func update(_ task: OmniTask) async throws {
        print("[TaskRepository] update called for task: \(task.title)")
        print("[TaskRepository] Task ID: \(task.id)")
        print("[TaskRepository] Task priority: \(task.priority.displayName)")
        print("[TaskRepository] Task dueDate: \(task.dueDate?.description ?? "nil")")
        print("[TaskRepository] Task projectId: \(task.projectId ?? "nil")")

        try await database.asyncWrite { db in
            var updatedTask = task
            updatedTask.updatedAt = Date()
            print("[TaskRepository] About to call updatedTask.update(db)...")
            try updatedTask.update(db)
            print("[TaskRepository] Database update complete")
        }
        print("[TaskRepository] Calling loadTasks to refresh...")
        loadTasks()
        print("[TaskRepository] loadTasks complete, tasks count: \(tasks.count)")
    }

    public func complete(_ task: OmniTask) async throws {
        var updatedTask = task
        updatedTask.isCompleted = true
        updatedTask.completedAt = Date()
        updatedTask.updatedAt = Date()
        let taskToSave = updatedTask

        try await database.asyncWrite { db in
            try taskToSave.update(db)
        }

        // Handle recurring tasks - check end conditions before creating next occurrence
        if let pattern = task.recurringPattern {
            // Increment the occurrence count
            let updatedPattern = pattern.incrementingOccurrence()

            // Only create next task if the pattern should continue
            if updatedPattern.shouldContinue {
                let nextTask = createNextRecurringTask(from: task, pattern: updatedPattern)
                try await create(nextTask)
            }
        }

        loadTasks()
    }

    /// Complete a task and all its incomplete subtasks in a single transaction
    public func completeWithSubtasks(_ task: OmniTask) async throws {
        let now = Date()

        try await database.asyncWrite { db in
            // Complete the parent task
            var updatedTask = task
            updatedTask.isCompleted = true
            updatedTask.completedAt = now
            updatedTask.updatedAt = now
            try updatedTask.update(db)

            // Complete all incomplete subtasks
            try db.execute(
                sql: "UPDATE tasks SET isCompleted = 1, completedAt = ?, updatedAt = ? WHERE parentTaskId = ? AND isCompleted = 0",
                arguments: [now, now, task.id]
            )
        }

        // Handle recurring tasks - check end conditions before creating next occurrence
        if let pattern = task.recurringPattern {
            // Increment the occurrence count
            let updatedPattern = pattern.incrementingOccurrence()

            // Only create next task if the pattern should continue
            if updatedPattern.shouldContinue {
                let nextTask = createNextRecurringTask(from: task, pattern: updatedPattern)
                try await create(nextTask)
            }
        }

        loadTasks()
    }

    public func uncomplete(_ task: OmniTask) async throws {
        var updatedTask = task
        updatedTask.isCompleted = false
        updatedTask.completedAt = nil
        updatedTask.updatedAt = Date()
        try await update(updatedTask)
    }

    public func updateSortOrder(taskId: String, newOrder: Int) async throws {
        try await database.asyncWrite { db in
            try db.execute(
                sql: "UPDATE tasks SET sortOrder = ?, updatedAt = ? WHERE id = ?",
                arguments: [newOrder, Date(), taskId]
            )
        }
        loadTasks()
    }

    // MARK: - Delete

    public func delete(_ task: OmniTask) async throws {
        _ = try await database.asyncWrite { db in
            try task.delete(db)
        }
        loadTasks()
    }

    // MARK: - Recurring Tasks

    private func createNextRecurringTask(from task: OmniTask, pattern: RecurringPattern) -> OmniTask {
        let nextDueDate = pattern.nextOccurrence(from: task.dueDate ?? Date())

        return OmniTask(
            title: task.title,
            notes: task.notes,
            projectId: task.projectId,
            parentTaskId: nil,
            priority: task.priority,
            dueDate: nextDueDate,
            recurringPattern: pattern,
            originalInput: task.originalInput
        )
    }

    // MARK: - Refresh

    public func refresh() {
        loadTasks()
    }

    // MARK: - Current Task

    /// Fetch the current task (only one should exist)
    public func fetchCurrentTask() async throws -> OmniTask? {
        try await database.asyncRead { db in
            try OmniTask
                .filter(Column("isCurrentTask") == true)
                .filter(Column("isCompleted") == false)
                .fetchOne(db)
        }
    }

    /// Set a task as the current task (clears any existing current task first)
    public func setCurrentTask(_ taskId: String) async throws {
        try await database.asyncWrite { db in
            // Clear any existing current task
            try db.execute(
                sql: "UPDATE tasks SET isCurrentTask = 0, updatedAt = ? WHERE isCurrentTask = 1",
                arguments: [Date()]
            )

            // Set the new current task
            try db.execute(
                sql: "UPDATE tasks SET isCurrentTask = 1, updatedAt = ? WHERE id = ?",
                arguments: [Date(), taskId]
            )
        }
        loadTasks()
    }

    /// Clear the current task (no task is current)
    public func clearCurrentTask() async throws {
        try await database.asyncWrite { db in
            try db.execute(
                sql: "UPDATE tasks SET isCurrentTask = 0, updatedAt = ? WHERE isCurrentTask = 1",
                arguments: [Date()]
            )
        }
        loadTasks()
    }

    // MARK: - Today Sort Order

    /// Update the today sort order for a task
    public func updateTodaySortOrder(_ taskId: String, order: Int) async throws {
        try await database.asyncWrite { db in
            try db.execute(
                sql: "UPDATE tasks SET todaySortOrder = ?, updatedAt = ? WHERE id = ?",
                arguments: [order, Date(), taskId]
            )
        }
        loadTasks()
    }

    /// Batch update today sort orders for multiple tasks
    public func updateTodaySortOrders(_ orderings: [(taskId: String, order: Int)]) async throws {
        try await database.asyncWrite { db in
            let now = Date()
            for (taskId, order) in orderings {
                try db.execute(
                    sql: "UPDATE tasks SET todaySortOrder = ?, updatedAt = ? WHERE id = ?",
                    arguments: [order, now, taskId]
                )
            }
        }
        loadTasks()
    }

    /// Fetch today's tasks sorted by todaySortOrder (flat list, not grouped by project)
    public func fetchTodayTasksFlat() async throws -> [OmniTask] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await database.asyncRead { db in
            try OmniTask
                .filter(Column("isCompleted") == false)
                .filter(Column("parentTaskId") == nil)  // Only top-level tasks
                .filter(Column("isCurrentTask") == false)  // Exclude current task (shown separately)
                .filter(Column("dueDate") >= startOfDay && Column("dueDate") < endOfDay)
                .order(
                    Column("todaySortOrder").ascNullsLast,
                    Column("createdAt").asc
                )
                .fetchAll(db)
        }
    }

    /// Fetch overdue tasks (due before start of today) as flat list
    public func fetchOverdueTasksFlat() async throws -> [OmniTask] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        return try await database.asyncRead { db in
            try OmniTask
                .filter(Column("isCompleted") == false)
                .filter(Column("parentTaskId") == nil)  // Only top-level tasks
                .filter(Column("isCurrentTask") == false)  // Exclude current task (shown separately)
                .filter(Column("dueDate") != nil && Column("dueDate") < startOfDay)
                .order(Column("dueDate").asc)
                .fetchAll(db)
        }
    }

    // MARK: - CloudKit Sync Support

    /// Fetch a single task by ID
    public func fetch(by id: String) async throws -> OmniTask? {
        try await database.asyncRead { db in
            try OmniTask.fetchOne(db, key: id)
        }
    }

    /// Upsert a task from CloudKit sync (insert or update based on existence)
    public func upsertFromCloud(_ task: OmniTask) async throws {
        try await database.asyncWrite { db in
            if try OmniTask.fetchOne(db, key: task.id) != nil {
                // Update existing
                var updatedTask = task
                try updatedTask.update(db)
            } else {
                // Insert new
                var newTask = task
                try newTask.insert(db)
            }
        }
        loadTasks()
    }
}
