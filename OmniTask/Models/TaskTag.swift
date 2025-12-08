import Foundation
import GRDB

/// Junction table for many-to-many relationship between tasks and tags
struct TaskTag: Codable, Equatable {
    var taskId: String
    var tagId: String
    var createdAt: Date

    init(
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
    static var databaseTableName: String { "task_tags" }

    enum Columns: String, ColumnExpression {
        case taskId, tagId, createdAt
    }
}
