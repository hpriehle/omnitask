import Foundation
import GRDB

/// A task in OmniTask
struct OmniTask: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var notes: String?
    var projectId: String?
    var parentTaskId: String?
    var priority: Priority
    var dueDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    var sortOrder: Int
    var todaySortOrder: Int?
    var isCurrentTask: Bool
    var recurringPattern: RecurringPattern?
    var originalInput: String?
    var createdAt: Date
    var updatedAt: Date

    init(
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

    var isOverdue: Bool {
        guard let dueDate = dueDate, !isCompleted else { return false }
        return dueDate < Date()
    }

    var isDueToday: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    var isSubtask: Bool {
        parentTaskId != nil
    }

    var isRecurring: Bool {
        recurringPattern != nil
    }
}

// MARK: - GRDB Support

extension OmniTask: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "tasks" }

    enum Columns: String, ColumnExpression {
        case id, title, notes, projectId, parentTaskId, priority
        case dueDate, isCompleted, completedAt, sortOrder, todaySortOrder, isCurrentTask
        case recurringPattern, originalInput, createdAt, updatedAt
    }
}

// MARK: - Database Value Conversions

extension OmniTask {
    init(row: Row) {
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

    func encode(to container: inout PersistenceContainer) {
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
