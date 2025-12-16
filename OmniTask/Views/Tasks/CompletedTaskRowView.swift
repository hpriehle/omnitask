import SwiftUI
import OmniTaskCore

/// A simplified row view for completed tasks
struct CompletedTaskRowView: View {
    let task: OmniTask
    let projects: [OmniTaskCore.Project]
    let onUncomplete: () -> Void

    @State private var isHovered = false

    private var project: OmniTaskCore.Project? {
        projects.first { $0.id == task.projectId }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Completed checkbox (can tap to uncomplete)
            Button {
                onUncomplete()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)

            // Task info
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .strikethrough()
                    .lineLimit(1)

                // Completion date
                if let completedAt = task.completedAt {
                    Text(completedAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            Spacer()

            // Project dot
            if let project = project {
                Circle()
                    .fill(project.swiftUIColor)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            CompletedTaskContextMenu(task: task)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        CompletedTaskRowView(
            task: OmniTask(
                title: "Completed task example",
                isCompleted: true,
                completedAt: Date().addingTimeInterval(-3600)
            ),
            projects: [],
            onUncomplete: {}
        )

        CompletedTaskRowView(
            task: OmniTask(
                title: "Another completed task",
                projectId: "1",
                isCompleted: true,
                completedAt: Date().addingTimeInterval(-86400)
            ),
            projects: [OmniTaskCore.Project(id: "1", name: "Work", color: "#3B82F6")],
            onUncomplete: {}
        )
    }
    .frame(width: 360)
}
