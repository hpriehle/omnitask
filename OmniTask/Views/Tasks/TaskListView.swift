import SwiftUI
import OmniTaskCore

/// Scrollable list of tasks
struct TaskListView: View {
    let tasks: [OmniTask]
    let projects: [OmniTaskCore.Project]
    let onComplete: (OmniTask) -> Void
    let onUpdate: (OmniTask) -> Void
    let onReorder: (IndexSet, Int) -> Void

    @State private var selectedTaskId: String?

    var body: some View {
        List {
            ForEach(tasks) { task in
                TaskRowView(
                    task: task,
                    projects: projects,
                    isSelected: selectedTaskId == task.id,
                    onComplete: { onComplete(task) },
                    onUpdate: { onUpdate($0) }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if selectedTaskId == task.id {
                            selectedTaskId = nil
                        } else {
                            selectedTaskId = task.id
                        }
                    }
                }
            }
            .onMove { source, destination in
                onReorder(source, destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Preview

#Preview {
    let tasks = [
        OmniTask(title: "Review proposal", priority: .high, dueDate: Date()),
        OmniTask(title: "Send emails", priority: .medium),
        OmniTask(title: "Update documentation", priority: .low)
    ]

    let projects = [
        OmniTaskCore.Project(name: "Work", color: "#3B82F6"),
        OmniTaskCore.Project(name: "Personal", color: "#10B981")
    ]

    TaskListView(
        tasks: tasks,
        projects: projects,
        onComplete: { _ in },
        onUpdate: { _ in },
        onReorder: { _, _ in }
    )
    .frame(width: 320, height: 400)
}
