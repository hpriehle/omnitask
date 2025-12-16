import Foundation
import SwiftUI

/// Task priority levels
public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0
    case low = 4
    case medium = 3
    case high = 2
    case urgent = 1

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        // Lower raw value = higher priority
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .none: return "No Priority"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    public var color: Color {
        switch self {
        case .none: return .secondary
        case .low: return .gray
        case .medium: return .yellow
        case .high: return .orange
        case .urgent: return .red
        }
    }

    public var icon: String {
        switch self {
        case .none: return ""
        case .low: return "arrow.down"
        case .medium: return "minus"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.2"
        }
    }

    /// Parse from string (e.g., from AI response)
    public static func from(string: String) -> Priority {
        switch string.lowercased() {
        case "urgent", "1": return .urgent
        case "high", "2": return .high
        case "medium", "normal", "3": return .medium
        case "low", "4": return .low
        default: return .medium
        }
    }
}
