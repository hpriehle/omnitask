import Foundation
import GRDB
import SwiftUI

/// A tag for categorizing tasks within a project
struct Tag: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var color: String
    var projectId: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        color: String = "#6B7280",
        projectId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.projectId = projectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var swiftUIColor: Color {
        Color(hex: color)
    }
}

// MARK: - GRDB Support

extension Tag: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "tags" }

    enum Columns: String, ColumnExpression {
        case id, name, color, projectId, createdAt, updatedAt
    }
}
