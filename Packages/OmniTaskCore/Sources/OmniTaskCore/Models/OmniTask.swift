import Foundation
import GRDB

/// A task in OmniTask
public struct OmniTask: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var notes: String?
    public var projectId: String?
    public var parentTaskId: String?
    public var priority: Priority
    public var dueDate: Date?
    public var isCompleted: Bool
    public var completedAt: Date?
    public var sortOrder: Int
    public var todaySortOrder: Int?
    public var isCurrentTask: Bool
    public var recurringPattern: RecurringPattern?
    public var originalInput: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        projectId: String? = nil,
        parentTaskId: String? = nil,
        priority: Priority = .medium,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        sortOrder: Int = 0,
        todaySortOrder: Int? = nil,
        isCurrentTask: Bool = false,
        recurringPattern: RecurringPattern? = nil,
        originalInput: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.projectId = projectId
        self.parentTaskId = parentTaskId
        self.priority = priority
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.todaySortOrder = todaySortOrder
        self.isCurrentTask = isCurrentTask
        self.recurringPattern = recurringPattern
        self.originalInput = originalInput
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    public var isOverdue: Bool {
        guard let dueDate = dueDate, !isCompleted else { return false }
        return dueDate < Date()
    }

    public var isDueToday: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    public var isSubtask: Bool {
        parentTaskId != nil
    }

    public var isRecurring: Bool {
        recurringPattern != nil
    }
}

// MARK: - GRDB Support

extension OmniTask: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "tasks" }

    public enum Columns: String, ColumnExpression {
        case id, title, notes, projectId, parentTaskId, priority
        case dueDate, isCompleted, completedAt, sortOrder, todaySortOrder, isCurrentTask
        case recurringPattern, originalInput, createdAt, updatedAt
    }
}

// MARK: - Database Value Conversions

extension OmniTask {
    public init(row: Row) {
        id = row["id"]
        title = row["title"]
        notes = row["notes"]
        projectId = row["projectId"]
        parentTaskId = row["parentTaskId"]
        priority = Priority(rawValue: row["priority"]) ?? .medium
        dueDate = row["dueDate"]
        isCompleted = row["isCompleted"]
        completedAt = row["completedAt"]
        sortOrder = row["sortOrder"]
        todaySortOrder = row["todaySortOrder"]
        isCurrentTask = row["isCurrentTask"] ?? false

        if let patternData = row["recurringPattern"] as? String,
           let data = patternData.data(using: .utf8) {
            recurringPattern = try? JSONDecoder().decode(RecurringPattern.self, from: data)
        } else {
            recurringPattern = nil
        }

        originalInput = row["originalInput"]
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["title"] = title
        container["notes"] = notes
        container["projectId"] = projectId
        container["parentTaskId"] = parentTaskId
        container["priority"] = priority.rawValue
        container["dueDate"] = dueDate
        container["isCompleted"] = isCompleted
        container["completedAt"] = completedAt
        container["sortOrder"] = sortOrder
        container["todaySortOrder"] = todaySortOrder
        container["isCurrentTask"] = isCurrentTask

        if let pattern = recurringPattern,
           let data = try? JSONEncoder().encode(pattern),
           let string = String(data: data, encoding: .utf8) {
            container["recurringPattern"] = string
        } else {
            container["recurringPattern"] = nil
        }

        container["originalInput"] = originalInput
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}
