import SwiftUI
import OmniTaskCore

/// Sticky card showing the current task with yellow styling
struct CurrentTaskCard: View {
    let task: OmniTask
    let onComplete: () async -> Void
    let onUnstar: () async -> Void
    let onTap: () -> Void

    @EnvironmentObject var projectRepository: ProjectRepository

    @State private var isCompleting = false

    private var project: Project? {
        guard let projectId = task.projectId else { return nil }
        return projectRepository.projects.first { $0.id == projectId }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                // Checkbox
                Button {
                    completeWithAnimation()
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(task.isCompleted ? .green : Color.yellow.opacity(0.8))
                        .scaleEffect(isCompleting ? 1.2 : 1.0)
                }
                .buttonStyle(.plain)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // Project dot
                        if let project = project {
                            Circle()
                                .fill(project.swiftUIColor)
                                .frame(width: 8, height: 8)
                        }

                        // Title
                        Text(task.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        // Recurring indicator
                        if task.isRecurring {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Due date
                    if let dueDate = task.dueDate {
                        Text(formatDueDate(dueDate))
                            .font(.caption)
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                    }
                }

                Spacer()

                // Unstar button
                Button {
                    Task { await onUnstar() }
                } label: {
                    Image(systemName: "star.fill")
                        .font(.body)
                        .foregroundStyle(.yellow)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.yellow.opacity(0.1))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.yellow.opacity(0.4), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Due Today"
        }

        if calendar.isDateInTomorrow(date) {
            return "Due Tomorrow"
        }

        let formatter = DateFormatter()
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateFormat = "MMM d"
        }

        return "Due \(formatter.string(from: date))"
    }

    private func completeWithAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isCompleting = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await onComplete()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        CurrentTaskCard(
            task: OmniTask(
                title: "Complete the iOS app redesign",
                projectId: "work",
                dueDate: Date()
            ),
            onComplete: {},
            onUnstar: {},
            onTap: {}
        )
        .environmentObject(ProjectRepository(database: DatabaseManager()))
    }
    .padding()
}
