import SwiftUI
import OmniTaskCore

/// Inline recurrence configuration component
struct RecurrenceOptionsView: View {
    @Binding var isRecurring: Bool
    @Binding var pattern: RecurringPattern?

    // Internal state for UI controls
    @State private var frequency: RecurringPattern.Frequency = .weekly
    @State private var interval: Int = 1
    @State private var selectedDays: Set<Int> = []
    @State private var dayOfMonth: Int = 1
    @State private var monthlyMode: MonthlyMode = .dayOfMonth
    @State private var weekOfMonth: RecurringPattern.WeekOfMonth = .first
    @State private var weekdayForOrdinal: Int = 1
    @State private var endConditionType: EndConditionType = .never
    @State private var endDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var occurrenceLimit: Int = 10

    enum MonthlyMode: String, CaseIterable {
        case dayOfMonth = "Day of month"
        case ordinalWeekday = "Weekday"
    }

    enum EndConditionType: String, CaseIterable {
        case never = "Never"
        case onDate = "Until date"
        case afterCount = "After occurrences"
    }

    private let weekdays: [(String, Int)] = [
        ("S", 1), ("M", 2), ("T", 3), ("W", 4), ("T", 5), ("F", 6), ("S", 7)
    ]

    private let weekdayNames: [(String, Int)] = [
        ("Sunday", 1), ("Monday", 2), ("Tuesday", 3), ("Wednesday", 4),
        ("Thursday", 5), ("Friday", 6), ("Saturday", 7)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Recurring toggle
            HStack {
                Toggle("Recurring", isOn: $isRecurring)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Text("Recurring")
                    .foregroundColor(.secondary)

                Spacer()
            }

            if isRecurring {
                VStack(alignment: .leading, spacing: 10) {
                    // Frequency picker
                    HStack {
                        Text("Repeat")
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $frequency) {
                            Text("Daily").tag(RecurringPattern.Frequency.daily)
                            Text("Weekly").tag(RecurringPattern.Frequency.weekly)
                            Text("Monthly").tag(RecurringPattern.Frequency.monthly)
                            Text("Yearly").tag(RecurringPattern.Frequency.yearly)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    // Interval stepper
                    HStack {
                        Text("Every")
                            .foregroundColor(.secondary)
                        Stepper(value: $interval, in: 1...99, label: {
                            Text("\(interval)")
                                .frame(minWidth: 24)
                        })
                        .fixedSize()
                        Text(intervalUnit)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    // Weekly: Day selection
                    if frequency == .weekly {
                        weeklyDayPicker
                    }

                    // Monthly options
                    if frequency == .monthly {
                        monthlyOptions
                    }

                    Divider()
                        .padding(.vertical, 4)

                    // End condition
                    endConditionPicker

                    // Preview
                    if let previewPattern = buildPattern() {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(previewPattern.displayString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .onChange(of: isRecurring) { newValue in
            if newValue {
                syncPatternToUI()
            }
            updatePattern()
        }
        .onChange(of: frequency) { _ in updatePattern() }
        .onChange(of: interval) { _ in updatePattern() }
        .onChange(of: selectedDays) { _ in updatePattern() }
        .onChange(of: dayOfMonth) { _ in updatePattern() }
        .onChange(of: monthlyMode) { _ in updatePattern() }
        .onChange(of: weekOfMonth) { _ in updatePattern() }
        .onChange(of: weekdayForOrdinal) { _ in updatePattern() }
        .onChange(of: endConditionType) { _ in updatePattern() }
        .onChange(of: endDate) { _ in updatePattern() }
        .onChange(of: occurrenceLimit) { _ in updatePattern() }
        .onAppear {
            syncPatternToUI()
        }
    }

    // MARK: - Weekly Day Picker

    private var weeklyDayPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("On")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(weekdays, id: \.1) { day in
                    Button {
                        toggleDay(day.1)
                    } label: {
                        Text(day.0)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 24, height: 24)
                            .background(selectedDays.contains(day.1) ? Color.accentColor : Color.primary.opacity(0.1))
                            .foregroundColor(selectedDays.contains(day.1) ? .white : .primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Monthly Options

    private var monthlyOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $monthlyMode) {
                ForEach(MonthlyMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            if monthlyMode == .dayOfMonth {
                HStack {
                    Text("On day")
                        .foregroundColor(.secondary)
                    Picker("", selection: $dayOfMonth) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
            } else {
                HStack {
                    Text("On the")
                        .foregroundColor(.secondary)
                    Picker("", selection: $weekOfMonth) {
                        ForEach(RecurringPattern.WeekOfMonth.allCases, id: \.self) { week in
                            Text(week.displayName).tag(week)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Picker("", selection: $weekdayForOrdinal) {
                        ForEach(weekdayNames, id: \.1) { name, value in
                            Text(name).tag(value)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
            }
        }
    }

    // MARK: - End Condition

    private var endConditionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ends")
                    .foregroundColor(.secondary)
                Picker("", selection: $endConditionType) {
                    ForEach(EndConditionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            if endConditionType == .onDate {
                HStack {
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                        .fixedSize()
                    Spacer()
                }
            }

            if endConditionType == .afterCount {
                HStack {
                    Text("After")
                        .foregroundColor(.secondary)
                    Stepper(value: $occurrenceLimit, in: 1...999, label: {
                        Text("\(occurrenceLimit)")
                            .frame(minWidth: 30)
                    })
                    .fixedSize()
                    Text("times")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

    private var intervalUnit: String {
        let unit: String
        switch frequency {
        case .daily: unit = "day"
        case .weekly: unit = "week"
        case .monthly: unit = "month"
        case .yearly: unit = "year"
        case .custom: unit = "day"
        }
        return interval == 1 ? unit : unit + "s"
    }

    private func toggleDay(_ day: Int) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }

    private func buildPattern() -> RecurringPattern? {
        guard isRecurring else { return nil }

        let endCondition: RecurringPattern.EndCondition
        switch endConditionType {
        case .never:
            endCondition = .never
        case .onDate:
            endCondition = .onDate(endDate)
        case .afterCount:
            endCondition = .afterOccurrences(occurrenceLimit)
        }

        switch frequency {
        case .weekly:
            return RecurringPattern(
                frequency: .weekly,
                interval: interval,
                daysOfWeek: selectedDays.isEmpty ? nil : selectedDays,
                endCondition: endCondition
            )
        case .monthly:
            if monthlyMode == .ordinalWeekday {
                return RecurringPattern(
                    frequency: .monthly,
                    interval: interval,
                    weekOfMonth: weekOfMonth,
                    weekdayForOrdinal: weekdayForOrdinal,
                    endCondition: endCondition
                )
            } else {
                return RecurringPattern(
                    frequency: .monthly,
                    interval: interval,
                    dayOfMonth: dayOfMonth,
                    endCondition: endCondition
                )
            }
        default:
            return RecurringPattern(
                frequency: frequency,
                interval: interval,
                endCondition: endCondition
            )
        }
    }

    private func updatePattern() {
        pattern = isRecurring ? buildPattern() : nil
    }

    private func syncPatternToUI() {
        guard let existingPattern = pattern else { return }

        frequency = existingPattern.frequency
        interval = existingPattern.interval

        if let days = existingPattern.daysOfWeek {
            selectedDays = days
        }

        if let day = existingPattern.dayOfMonth {
            dayOfMonth = day
            monthlyMode = .dayOfMonth
        }

        if let week = existingPattern.weekOfMonth, let weekday = existingPattern.weekdayForOrdinal {
            weekOfMonth = week
            weekdayForOrdinal = weekday
            monthlyMode = .ordinalWeekday
        }

        switch existingPattern.endCondition {
        case .never:
            endConditionType = .never
        case .onDate(let date):
            endConditionType = .onDate
            endDate = date
        case .afterOccurrences(let count):
            endConditionType = .afterCount
            occurrenceLimit = count
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var isRecurring = true
        @State private var pattern: RecurringPattern? = .weekly

        var body: some View {
            VStack {
                RecurrenceOptionsView(
                    isRecurring: $isRecurring,
                    pattern: $pattern
                )
                .padding()

                Divider()

                if let pattern {
                    Text("Pattern: \(pattern.displayString)")
                        .font(.caption)
                        .padding()
                }
            }
            .frame(width: 300)
        }
    }

    return PreviewWrapper()
}
