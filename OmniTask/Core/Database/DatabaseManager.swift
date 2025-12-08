import Foundation
import GRDB

/// Manages the SQLite database using GRDB
final class DatabaseManager {
    let dbQueue: DatabaseQueue

    init() {
        do {
            // Get the app's Application Support directory
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbDirectory = appSupport.appendingPathComponent("OmniTask", isDirectory: true)

            // Create directory if needed
            try fileManager.createDirectory(at: dbDirectory, withIntermediateDirectories: true)

            let dbPath = dbDirectory.appendingPathComponent("omnitask.db").path
            dbQueue = try DatabaseQueue(path: dbPath)

            // Run migrations
            try migrator.migrate(dbQueue)

        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initial") { db in
            // Projects table
            try db.create(table: "projects") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("color", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Tasks table
            try db.create(table: "tasks") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("notes", .text)
                t.column("projectId", .text).references("projects", onDelete: .setNull)
                t.column("parentTaskId", .text).references("tasks", onDelete: .cascade)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("dueDate", .datetime)
                t.column("isCompleted", .boolean).notNull().defaults(to: false)
                t.column("completedAt", .datetime)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("recurringPattern", .text)
                t.column("originalInput", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Create indexes
            try db.create(index: "idx_tasks_projectId", on: "tasks", columns: ["projectId"])
            try db.create(index: "idx_tasks_parentTaskId", on: "tasks", columns: ["parentTaskId"])
            try db.create(index: "idx_tasks_dueDate", on: "tasks", columns: ["dueDate"])
            try db.create(index: "idx_tasks_isCompleted", on: "tasks", columns: ["isCompleted"])
        }

        migrator.registerMigration("v2_tags") { db in
            // Tags table - project-specific tags
            try db.create(table: "tags") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull().defaults(to: "#6B7280")
                t.column("projectId", .text).notNull().references("projects", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Task-Tag junction table for many-to-many relationship
            try db.create(table: "task_tags") { t in
                t.column("taskId", .text).notNull().references("tasks", onDelete: .cascade)
                t.column("tagId", .text).notNull().references("tags", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull()
                t.primaryKey(["taskId", "tagId"])
            }

            // Create indexes
            try db.create(index: "idx_tags_projectId", on: "tags", columns: ["projectId"])
            try db.create(index: "idx_task_tags_taskId", on: "task_tags", columns: ["taskId"])
            try db.create(index: "idx_task_tags_tagId", on: "task_tags", columns: ["tagId"])
        }

        migrator.registerMigration("v3_current_task") { db in
            // Add todaySortOrder for custom ordering in Today tab
            try db.alter(table: "tasks") { t in
                t.add(column: "todaySortOrder", .integer)
            }

            // Add isCurrentTask flag (only one task should be current at a time)
            try db.alter(table: "tasks") { t in
                t.add(column: "isCurrentTask", .boolean).notNull().defaults(to: false)
            }

            // Create index for quick current task lookup
            try db.create(index: "idx_tasks_isCurrentTask", on: "tasks", columns: ["isCurrentTask"])
        }

        return migrator
    }

    // MARK: - Utility Methods

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }

    func asyncRead<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.read(block)
    }

    func asyncWrite<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.write(block)
    }
}
