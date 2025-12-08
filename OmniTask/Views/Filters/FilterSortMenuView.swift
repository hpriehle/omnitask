import SwiftUI

/// Popover menu for filtering and sorting tasks
struct FilterSortMenuView: View {
    @Binding var settings: FilterSortSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Sort section
                sortSection

                Divider()
                    .padding(.vertical, 8)

                // Show completed toggle
                showCompletedSection

                Divider()
                    .padding(.vertical, 8)

                // Priority filter section
                prioritySection

                Divider()
                    .padding(.vertical, 8)

                // Due date filter section
                dueDateSection

                // Clear filters button
                if settings.hasActiveFilters {
                    Divider()
                        .padding(.vertical, 8)

                    clearFiltersButton
                }
            }
            .padding(16)
        }
        .frame(width: 280, height: 400)
    }

    // MARK: - Sort Section

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sort By")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    SortOptionButton(
                        option: option,
                        isSelected: settings.sortOption == option
                    ) {
                        settings.sortOption = option
                    }
                }
            }
        }
    }

    // MARK: - Show Completed Section

    private var showCompletedSection: some View {
        HStack {
            Text("Show Completed")
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Toggle("", isOn: $settings.showCompleted)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8)
        }
    }

    // MARK: - Priority Section

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Priority")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                ForEach(Priority.allCases, id: \.self) { priority in
                    PriorityCheckbox(
                        priority: priority,
                        isSelected: settings.selectedPriorities.contains(priority)
                    ) {
                        if settings.selectedPriorities.contains(priority) {
                            // Don't allow deselecting all priorities
                            if settings.selectedPriorities.count > 1 {
                                settings.selectedPriorities.remove(priority)
                            }
                        } else {
                            settings.selectedPriorities.insert(priority)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Due Date Section

    private var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Due Date")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                ForEach(DueDateFilter.allCases, id: \.self) { filter in
                    DueDateOptionButton(
                        filter: filter,
                        isSelected: settings.dueDateFilter == filter
                    ) {
                        settings.dueDateFilter = filter
                    }
                }
            }
        }
    }

    // MARK: - Clear Filters Button

    private var clearFiltersButton: some View {
        Button {
            settings.reset()
        } label: {
            Text("Clear Filters")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sort Option Button

private struct SortOptionButton: View {
    let option: SortOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(option.displayName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Priority Checkbox

private struct PriorityCheckbox: View {
    let priority: Priority
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? priority.color : .secondary)

                Text(priority.displayName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? priority.color.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Due Date Option Button

private struct DueDateOptionButton: View {
    let filter: DueDateFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(filter.displayName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    FilterSortMenuView(settings: .constant(.default))
        .frame(width: 300, height: 450)
}
