import Foundation
import SwiftUI

/// Task priority levels
enum Priority: Int, Codable, CaseIterable, Comparable {
    case none = 0
    case low = 4
    case medium = 3
    case high = 2
    case urgent = 1

    static func < (lhs: Priority, rhs: Priority) -> Bool {
        // Lower raw value = higher priority
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .none: return "No Priority"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    var color: Color {
        switch self {
        case .none: return .secondary
        case .low: return .gray
        case .medium: return .yellow
        case .high: return .orange
        case .urgent: return .red
        }
    }

    var icon: String {
        switch self {
        case .none: return ""
        case .low: return "arrow.down"
        case .medium: return "minus"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.2"
        }
    }

    /// Parse from string (e.g., from AI response)
    static func from(string: String) -> Priority {
        switch string.lowercased() {
        case "urgent", "1": return .urgent
        case "high", "2": return .high
        case "medium", "normal", "3": return .medium
        case "low", "4": return .low
        default: return .medium
        }
    }
}
