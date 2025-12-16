import Foundation
import GRDB
import SwiftUI

/// A tag for categorizing tasks within a project
public struct Tag: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var color: String
    public var projectId: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
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

    public var swiftUIColor: Color {
        Color(hex: color)
    }
}

// MARK: - GRDB Support

extension Tag: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "tags" }

    public enum Columns: String, ColumnExpression {
        case id, name, color, projectId, createdAt, updatedAt
    }
}
