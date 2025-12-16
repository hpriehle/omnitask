import Foundation

/// Defines how a task recurs
public struct RecurringPattern: Codable, Equatable, Sendable {
    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case daily
        case weekly
        case monthly
        case yearly
        case custom
    }

    /// Represents which week of the month for ordinal patterns (e.g., "2nd Sunday")
    public enum WeekOfMonth: Int, Codable, CaseIterable, Sendable {
        case first = 1
        case second = 2
        case third = 3
        case fourth = 4
        case last = -1

        public var displayName: String {
            switch self {
            case .first: return "1st"
            case .second: return "2nd"
            case .third: return "3rd"
            case .fourth: return "4th"
            case .last: return "Last"
            }
        }
    }

    /// How the recurrence should end
    public enum EndCondition: Codable, Equatable, Sendable {
        case never
        case onDate(Date)
        case afterOccurrences(Int)
    }

    public var frequency: Frequency
    public var interval: Int // Every N days/weeks/months
    public var daysOfWeek: Set<Int>? // 1 = Sunday, 7 = Saturday (for weekly)
    public var dayOfMonth: Int? // For monthly (1-31)
    public var weekOfMonth: WeekOfMonth? // For ordinal monthly (e.g., "2nd Sunday")
    public var weekdayForOrdinal: Int? // The weekday to use with weekOfMonth (1 = Sunday, 7 = Saturday)
    public var endCondition: EndCondition // When to stop recurring
    public var occurrenceCount: Int // Track completed occurrences

    public init(
        frequency: Frequency,
        interval: Int = 1,
        daysOfWeek: Set<Int>? = nil,
        dayOfMonth: Int? = nil,
        weekOfMonth: WeekOfMonth? = nil,
        weekdayForOrdinal: Int? = nil,
        endCondition: EndCondition = .never,
        occurrenceCount: Int = 0
    ) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.dayOfMonth = dayOfMonth
        self.weekOfMonth = weekOfMonth
        self.weekdayForOrdinal = weekdayForOrdinal
        self.endCondition = endCondition
        self.occurrenceCount = occurrenceCount
    }

    // MARK: - End Condition Helpers

    /// Whether the pattern should continue creating new occurrences
    public var shouldContinue: Bool {
        switch endCondition {
        case .never:
            return true
        case .onDate(let endDate):
            return Date() <= endDate
        case .afterOccurrences(let maxCount):
            return occurrenceCount < maxCount
        }
    }

    /// Returns a copy with incremented occurrence count
    public func incrementingOccurrence() -> RecurringPattern {
        var copy = self
        copy.occurrenceCount += 1
        return copy
    }

    // MARK: - Convenience Initializers

    public static var daily: RecurringPattern {
        RecurringPattern(frequency: .daily)
    }

    public static var weekly: RecurringPattern {
        RecurringPattern(frequency: .weekly)
    }

    public static var monthly: RecurringPattern {
        RecurringPattern(frequency: .monthly)
    }

    public static func weekly(on days: Set<Int>) -> RecurringPattern {
        RecurringPattern(frequency: .weekly, daysOfWeek: days)
    }

    // MARK: - Next Occurrence

    public func nextOccurrence(from date: Date) -> Date {
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

            // Handle ordinal weekday pattern (e.g., "2nd Sunday of the month")
            if let week = weekOfMonth, let weekday = weekdayForOrdinal {
                return nextOrdinalWeekdayOccurrence(from: date, weekOfMonth: week, weekday: weekday)
            }

            // Handle specific day of month
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

    /// Calculates the next occurrence for ordinal weekday patterns (e.g., "2nd Sunday of the month")
    private func nextOrdinalWeekdayOccurrence(from date: Date, weekOfMonth: WeekOfMonth, weekday: Int) -> Date {
        let calendar = Calendar.current

        // Start from next month (interval months ahead)
        guard let nextMonthDate = calendar.date(byAdding: .month, value: interval, to: date) else {
            return date
        }

        // Get the first day of that month
        let components = calendar.dateComponents([.year, .month], from: nextMonthDate)
        guard let firstOfMonth = calendar.date(from: components) else {
            return date
        }

        if weekOfMonth == .last {
            // Find the last occurrence of the weekday in the month
            return lastWeekdayOfMonth(weekday: weekday, in: firstOfMonth) ?? date
        } else {
            // Find the Nth occurrence of the weekday
            return nthWeekdayOfMonth(weekday: weekday, n: weekOfMonth.rawValue, in: firstOfMonth) ?? date
        }
    }

    /// Finds the Nth occurrence of a weekday in the given month
    private func nthWeekdayOfMonth(weekday: Int, n: Int, in monthDate: Date) -> Date? {
        let calendar = Calendar.current

        // Get first day of the month
        let components = calendar.dateComponents([.year, .month], from: monthDate)
        guard let firstOfMonth = calendar.date(from: components) else { return nil }

        // Find the first occurrence of the target weekday
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        var daysToAdd = weekday - firstWeekday
        if daysToAdd < 0 { daysToAdd += 7 }

        guard let firstOccurrence = calendar.date(byAdding: .day, value: daysToAdd, to: firstOfMonth) else {
            return nil
        }

        // Add (n-1) weeks to get to the Nth occurrence
        guard let nthOccurrence = calendar.date(byAdding: .weekOfMonth, value: n - 1, to: firstOccurrence) else {
            return nil
        }

        // Verify it's still in the same month
        let nthMonth = calendar.component(.month, from: nthOccurrence)
        let targetMonth = calendar.component(.month, from: monthDate)
        if nthMonth != targetMonth {
            return nil // Nth occurrence doesn't exist in this month
        }

        return nthOccurrence
    }

    /// Finds the last occurrence of a weekday in the given month
    private func lastWeekdayOfMonth(weekday: Int, in monthDate: Date) -> Date? {
        let calendar = Calendar.current

        // Get the last day of the month
        let components = calendar.dateComponents([.year, .month], from: monthDate)
        guard let firstOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth),
              let lastOfMonth = calendar.date(byAdding: .day, value: range.count - 1, to: firstOfMonth) else {
            return nil
        }

        // Find the last occurrence of the target weekday
        let lastWeekday = calendar.component(.weekday, from: lastOfMonth)
        var daysToSubtract = lastWeekday - weekday
        if daysToSubtract < 0 { daysToSubtract += 7 }

        return calendar.date(byAdding: .day, value: -daysToSubtract, to: lastOfMonth)
    }

    // MARK: - Display

    public var displayString: String {
        var base: String

        switch frequency {
        case .daily:
            base = interval == 1 ? "Daily" : "Every \(interval) days"

        case .weekly:
            if let days = daysOfWeek, !days.isEmpty {
                let dayNames = days.sorted().compactMap { weekdayName($0) }
                if interval == 1 {
                    base = "Weekly on \(dayNames.joined(separator: ", "))"
                } else {
                    base = "Every \(interval) weeks on \(dayNames.joined(separator: ", "))"
                }
            } else {
                base = interval == 1 ? "Weekly" : "Every \(interval) weeks"
            }

        case .monthly:
            // Ordinal weekday pattern (e.g., "2nd Sunday")
            if let week = weekOfMonth, let weekday = weekdayForOrdinal, let dayName = weekdayName(weekday) {
                let ordinal = week.displayName
                if interval == 1 {
                    base = "Monthly on the \(ordinal) \(dayName)"
                } else {
                    base = "Every \(interval) months on the \(ordinal) \(dayName)"
                }
            }
            // Specific day of month
            else if let day = dayOfMonth {
                let ordinalDay = ordinalString(for: day)
                if interval == 1 {
                    base = "Monthly on the \(ordinalDay)"
                } else {
                    base = "Every \(interval) months on the \(ordinalDay)"
                }
            } else {
                base = interval == 1 ? "Monthly" : "Every \(interval) months"
            }

        case .yearly:
            base = interval == 1 ? "Yearly" : "Every \(interval) years"

        case .custom:
            base = "Every \(interval) days"
        }

        // Append end condition if set
        switch endCondition {
        case .never:
            break
        case .onDate(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            base += " until \(formatter.string(from: date))"
        case .afterOccurrences(let count):
            let remaining = count - occurrenceCount
            if remaining > 0 {
                base += " (\(remaining) remaining)"
            }
        }

        return base
    }

    /// Converts a day number to ordinal string (1st, 2nd, 3rd, etc.)
    private func ordinalString(for day: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
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

    /// Weekday patterns for parsing
    private static let weekdayPatterns: [(String, Int)] = [
        ("sunday", 1), ("sun", 1),
        ("monday", 2), ("mon", 2),
        ("tuesday", 3), ("tue", 3),
        ("wednesday", 4), ("wed", 4),
        ("thursday", 5), ("thu", 5),
        ("friday", 6), ("fri", 6),
        ("saturday", 7), ("sat", 7)
    ]

    /// Ordinal patterns for parsing (e.g., "1st", "2nd", "first", "second")
    private static let ordinalPatterns: [(String, WeekOfMonth)] = [
        ("1st", .first), ("first", .first),
        ("2nd", .second), ("second", .second),
        ("3rd", .third), ("third", .third),
        ("4th", .fourth), ("fourth", .fourth),
        ("last", .last)
    ]

    public static func parse(from string: String) -> RecurringPattern? {
        let lowercased = string.lowercased()

        // Parse interval (e.g., "every 2 weeks", "every other week")
        var interval = 1
        if lowercased.contains("every other") || lowercased.contains("every 2") {
            interval = 2
        } else if let match = lowercased.range(of: #"every\s+(\d+)"#, options: .regularExpression) {
            let numberPart = lowercased[match].replacingOccurrences(of: "every", with: "").trimmingCharacters(in: .whitespaces)
            interval = Int(numberPart) ?? 1
        }

        // Check for ordinal monthly pattern first (e.g., "2nd Sunday of the month")
        if let ordinalResult = parseOrdinalMonthly(from: lowercased) {
            return RecurringPattern(
                frequency: .monthly,
                interval: interval,
                weekOfMonth: ordinalResult.week,
                weekdayForOrdinal: ordinalResult.weekday
            )
        }

        // Simple patterns
        if lowercased.contains("daily") || lowercased.contains("every day") {
            return RecurringPattern(frequency: .daily, interval: interval)
        }

        if lowercased.contains("yearly") || lowercased.contains("every year") || lowercased.contains("annually") {
            return RecurringPattern(frequency: .yearly, interval: interval)
        }

        if lowercased.contains("monthly") || lowercased.contains("every month") {
            return RecurringPattern(frequency: .monthly, interval: interval)
        }

        if lowercased.contains("weekly") || lowercased.contains("every week") {
            return RecurringPattern(frequency: .weekly, interval: interval)
        }

        // Parse "every Monday", "every Mon/Wed/Fri", etc.
        var foundDays = Set<Int>()
        for (pattern, day) in weekdayPatterns {
            if lowercased.contains(pattern) {
                foundDays.insert(day)
            }
        }

        if !foundDays.isEmpty {
            return RecurringPattern(frequency: .weekly, interval: interval, daysOfWeek: foundDays)
        }

        return nil
    }

    /// Parses ordinal monthly patterns like "2nd Sunday", "last Friday of the month"
    private static func parseOrdinalMonthly(from string: String) -> (week: WeekOfMonth, weekday: Int)? {
        var foundWeek: WeekOfMonth?
        var foundWeekday: Int?

        // Look for ordinal
        for (pattern, week) in ordinalPatterns {
            if string.contains(pattern) {
                foundWeek = week
                break
            }
        }

        // Look for weekday
        for (pattern, day) in weekdayPatterns {
            if string.contains(pattern) {
                foundWeekday = day
                break
            }
        }

        // Only return if we found both ordinal and weekday, and it looks like a monthly pattern
        if let week = foundWeek, let weekday = foundWeekday {
            // Must have "month" or ordinal context (like "2nd Sunday" without "weekly")
            if string.contains("month") || (!string.contains("week") && !string.contains("daily")) {
                return (week, weekday)
            }
        }

        return nil
    }

    // MARK: - Convenience Initializers for Ordinal Monthly

    /// Creates a monthly pattern for the Nth weekday (e.g., "2nd Sunday")
    public static func monthly(on week: WeekOfMonth, weekday: Int) -> RecurringPattern {
        RecurringPattern(
            frequency: .monthly,
            weekOfMonth: week,
            weekdayForOrdinal: weekday
        )
    }
}
