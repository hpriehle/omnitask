import Foundation

/// Defines how a task recurs
struct RecurringPattern: Codable, Equatable {
    enum Frequency: String, Codable, CaseIterable {
        case daily
        case weekly
        case monthly
        case yearly
        case custom
    }

    var frequency: Frequency
    var interval: Int // Every N days/weeks/months
    var daysOfWeek: Set<Int>? // 1 = Sunday, 7 = Saturday (for weekly)
    var dayOfMonth: Int? // For monthly (1-31)

    init(
        frequency: Frequency,
        interval: Int = 1,
        daysOfWeek: Set<Int>? = nil,
        dayOfMonth: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.dayOfMonth = dayOfMonth
    }

    // MARK: - Convenience Initializers

    static var daily: RecurringPattern {
        RecurringPattern(frequency: .daily)
    }

    static var weekly: RecurringPattern {
        RecurringPattern(frequency: .weekly)
    }

    static var monthly: RecurringPattern {
        RecurringPattern(frequency: .monthly)
    }

    static func weekly(on days: Set<Int>) -> RecurringPattern {
        RecurringPattern(frequency: .weekly, daysOfWeek: days)
    }

    // MARK: - Next Occurrence

    func nextOccurrence(from date: Date) -> Date {
        let calendar = Calendar.current

        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date) ?? date

        case .weekly:
            if let daysOfWeek = daysOfWeek, !daysOfWeek.isEmpty {
                return nextWeekdayOccurrence(from: date, daysOfWeek: daysOfWeek)
            } else {
                return calendar.date(byAdding: .weekOfYear, value: interval, to: date) ?? date
            }

        case .monthly:
            var components = DateComponents()
            components.month = interval

            if let day = dayOfMonth {
                var nextDate = calendar.date(byAdding: components, to: date) ?? date
                let nextComponents = calendar.dateComponents([.year, .month], from: nextDate)
                var targetComponents = nextComponents
                targetComponents.day = min(day, calendar.range(of: .day, in: .month, for: nextDate)?.count ?? day)
                nextDate = calendar.date(from: targetComponents) ?? nextDate
                return nextDate
            }

            return calendar.date(byAdding: components, to: date) ?? date

        case .yearly:
            return calendar.date(byAdding: .year, value: interval, to: date) ?? date

        case .custom:
            return calendar.date(byAdding: .day, value: interval, to: date) ?? date
        }
    }

    private func nextWeekdayOccurrence(from date: Date, daysOfWeek: Set<Int>) -> Date {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: date)
        let sortedDays = daysOfWeek.sorted()

        // Find the next day this week
        for day in sortedDays where day > currentWeekday {
            let daysToAdd = day - currentWeekday
            if let nextDate = calendar.date(byAdding: .day, value: daysToAdd, to: date) {
                return nextDate
            }
        }

        // If no day found this week, go to first day of next interval week
        if let firstDay = sortedDays.first {
            let daysUntilFirstDay = (7 - currentWeekday + firstDay) + (7 * (interval - 1))
            if let nextDate = calendar.date(byAdding: .day, value: daysUntilFirstDay, to: date) {
                return nextDate
            }
        }

        // Fallback
        return calendar.date(byAdding: .day, value: 7 * interval, to: date) ?? date
    }

    // MARK: - Display

    var displayString: String {
        switch frequency {
        case .daily:
            return interval == 1 ? "Daily" : "Every \(interval) days"

        case .weekly:
            if let days = daysOfWeek, !days.isEmpty {
                let dayNames = days.sorted().compactMap { weekdayName($0) }
                return "Weekly on \(dayNames.joined(separator: ", "))"
            }
            return interval == 1 ? "Weekly" : "Every \(interval) weeks"

        case .monthly:
            if let day = dayOfMonth {
                return interval == 1 ? "Monthly on day \(day)" : "Every \(interval) months on day \(day)"
            }
            return interval == 1 ? "Monthly" : "Every \(interval) months"

        case .yearly:
            return interval == 1 ? "Yearly" : "Every \(interval) years"

        case .custom:
            return "Every \(interval) days"
        }
    }

    private func weekdayName(_ weekday: Int) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        var components = DateComponents()
        components.weekday = weekday
        if let date = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) {
            return formatter.string(from: date)
        }
        return nil
    }

    // MARK: - Parsing from Natural Language

    static func parse(from string: String) -> RecurringPattern? {
        let lowercased = string.lowercased()

        if lowercased.contains("daily") || lowercased.contains("every day") {
            return .daily
        }

        if lowercased.contains("weekly") || lowercased.contains("every week") {
            return .weekly
        }

        if lowercased.contains("monthly") || lowercased.contains("every month") {
            return .monthly
        }

        // Parse "every Monday", "every Mon/Wed/Fri", etc.
        let weekdayPatterns: [(String, Int)] = [
            ("sunday", 1), ("sun", 1),
            ("monday", 2), ("mon", 2),
            ("tuesday", 3), ("tue", 3),
            ("wednesday", 4), ("wed", 4),
            ("thursday", 5), ("thu", 5),
            ("friday", 6), ("fri", 6),
            ("saturday", 7), ("sat", 7)
        ]

        var foundDays = Set<Int>()
        for (pattern, day) in weekdayPatterns {
            if lowercased.contains(pattern) {
                foundDays.insert(day)
            }
        }

        if !foundDays.isEmpty {
            return .weekly(on: foundDays)
        }

        return nil
    }
}
