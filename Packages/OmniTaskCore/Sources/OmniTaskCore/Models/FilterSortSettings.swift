import Foundation

/// Sort options for task list
public enum SortOption: String, Codable, CaseIterable, Sendable {
    case dueDateAsc = "due_date_asc"
    case dueDateDesc = "due_date_desc"
    case priorityAsc = "priority_asc"
    case priorityDesc = "priority_desc"
    case titleAsc = "title_asc"
    case titleDesc = "title_desc"
    case createdAsc = "created_asc"
    case createdDesc = "created_desc"

    public var displayName: String {
        switch self {
        case .dueDateAsc: return "Due Date ↑"
        case .dueDateDesc: return "Due Date ↓"
        case .priorityAsc: return "Priority ↑"
        case .priorityDesc: return "Priority ↓"
        case .titleAsc: return "A-Z"
        case .titleDesc: return "Z-A"
        case .createdAsc: return "Created ↑"
        case .createdDesc: return "Created ↓"
        }
    }
}

/// Due date filter presets
public enum DueDateFilter: String, Codable, CaseIterable, Sendable {
    case all = "all"
    case overdue = "overdue"
    case today = "today"
    case thisWeek = "this_week"
    case thisMonth = "this_month"
    case noDueDate = "no_due_date"

    public var displayName: String {
        switch self {
        case .all: return "All"
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .noDueDate: return "No Due Date"
        }
    }
}

/// Filter and sort settings for task list
public struct FilterSortSettings: Codable, Equatable, Sendable {
    public var sortOption: SortOption
    public var showCompleted: Bool
    public var selectedPriorities: Set<Priority>
    public var dueDateFilter: DueDateFilter

    public init(
        sortOption: SortOption = .dueDateAsc,
        showCompleted: Bool = false,
        selectedPriorities: Set<Priority> = Set(Priority.allCases),
        dueDateFilter: DueDateFilter = .all
    ) {
        self.sortOption = sortOption
        self.showCompleted = showCompleted
        self.selectedPriorities = selectedPriorities
        self.dueDateFilter = dueDateFilter
    }

    /// Default settings (no filters active)
    public static let `default` = FilterSortSettings(
        sortOption: .dueDateAsc,
        showCompleted: false,
        selectedPriorities: Set(Priority.allCases),
        dueDateFilter: .all
    )

    /// Check if any non-default filters/sort are active
    public var hasActiveFilters: Bool {
        sortOption != .dueDateAsc ||
        showCompleted ||
        selectedPriorities != Set(Priority.allCases) ||
        dueDateFilter != .all
    }

    /// Reset to default settings
    public mutating func reset() {
        self = .default
    }
}

// MARK: - UserDefaults Persistence

public extension FilterSortSettings {
    private static let userDefaultsKey = "filterSortSettings"

    /// Save settings to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
        }
    }

    /// Load settings from UserDefaults
    static func load() -> FilterSortSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(FilterSortSettings.self, from: data) else {
            return .default
        }
        return settings
    }
}

// MARK: - Custom Codable for FilterSortSettings

extension FilterSortSettings {
    enum CodingKeys: String, CodingKey {
        case sortOption
        case showCompleted
        case selectedPriorities
        case dueDateFilter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sortOption = try container.decode(SortOption.self, forKey: .sortOption)
        showCompleted = try container.decode(Bool.self, forKey: .showCompleted)
        let priorityArray = try container.decode([Priority].self, forKey: .selectedPriorities)
        selectedPriorities = Set(priorityArray)
        dueDateFilter = try container.decode(DueDateFilter.self, forKey: .dueDateFilter)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sortOption, forKey: .sortOption)
        try container.encode(showCompleted, forKey: .showCompleted)
        try container.encode(Array(selectedPriorities), forKey: .selectedPriorities)
        try container.encode(dueDateFilter, forKey: .dueDateFilter)
    }
}
