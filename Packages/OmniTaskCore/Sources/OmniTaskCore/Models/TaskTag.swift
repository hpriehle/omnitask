import Foundation
import GRDB

/// Junction table for many-to-many relationship between tasks and tags
public struct TaskTag: Codable, Equatable, Sendable {
    public var taskId: String
    public var tagId: String
    public var createdAt: Date

    public init(
        taskId: String,
        tagId: String,
        createdAt: Date = Date()
    ) {
        self.taskId = taskId
        self.tagId = tagId
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Support

extension TaskTag: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "task_tags" }

    public enum Columns: String, ColumnExpression {
        case taskId, tagId, createdAt
    }
}
