import Foundation
import GRDB

/// A project/category for grouping tasks
struct Project: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var description: String?
    var color: String?
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        color: String? = nil,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.color = color
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    /// Returns the SwiftUI Color from the hex string
    var swiftUIColor: Color {
        Color(hex: color ?? "#3B82F6")
    }
}

// MARK: - GRDB Support

extension Project: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "projects" }

    enum Columns: String, ColumnExpression {
        case id, name, description, color, sortOrder, isArchived, createdAt, updatedAt
    }
}

// MARK: - SwiftUI Color Extension

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: // ARGB
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (59, 130, 246) // Default blue
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
