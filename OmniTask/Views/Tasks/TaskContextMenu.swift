import SwiftUI
import AppKit
import OmniTaskCore

/// Context menu for task actions (Copy, Set Priority, Move to Project)
struct TaskContextMenu: View {
    let task: OmniTask
    let subtasks: [OmniTask]
    let projects: [OmniTaskCore.Project]
    let onUpdate: (OmniTask) -> Void

    /// Controls which menu options are shown
    var showSubtasksOption: Bool = true
    var showPriorityMenu: Bool = true
    var showProjectMenu: Bool = true

    // Copy checkboxes state (persisted via AppStorage)
    @AppStorage("copyIncludeTitle") private var includeTitle = true
    @AppStorage("copyIncludeSubtasks") private var includeSubtasks = true
    @AppStorage("copyIncludePriority") private var includePriority = false
    @AppStorage("copyIncludeDueDate") private var includeDueDate = false
    @AppStorage("copyIncludeNotes") private var includeNotes = true

    init(task: OmniTask, subtasks: [OmniTask], projects: [OmniTaskCore.Project], onUpdate: @escaping (OmniTask) -> Void, showSubtasksOption: Bool = true, showPriorityMenu: Bool = true, showProjectMenu: Bool = true) {
        self.task = task
        self.subtasks = subtasks
        self.projects = projects
        self.onUpdate = onUpdate
        self.showSubtasksOption = showSubtasksOption
        self.showPriorityMenu = showPriorityMenu
        self.showProjectMenu = showProjectMenu
        print("[TaskContextMenu] INIT - task: '\(task.title)', subtasks count: \(subtasks.count)")
        for (i, st) in subtasks.enumerated() {
            print("[TaskContextMenu] INIT - subtask[\(i)]: '\(st.title)'")
        }
    }

    var body: some View {
        // Copy submenu
        Menu {
            Toggle("Title", isOn: $includeTitle)

            if showSubtasksOption {
                Toggle("Subtasks (\(subtasks.count))", isOn: $includeSubtasks)
            }

            Toggle("Priority", isOn: $includePriority)
            Toggle("Due Date", isOn: $includeDueDate)
            Toggle("Notes", isOn: $includeNotes)

            Divider()

            Button("Copy") {
                copyToClipboard()
            }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        if showPriorityMenu || showProjectMenu {
            Divider()
        }

        // Set Priority submenu
        if showPriorityMenu {
            Menu {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Button {
                        var updated = task
                        updated.priority = priority
                        onUpdate(updated)
                    } label: {
                        HStack {
                            if !priority.icon.isEmpty {
                                Image(systemName: priority.icon)
                            }
                            Text(priority.displayName)
                        }
                    }
                    .disabled(task.priority == priority)
                }
            } label: {
                Label("Set Priority", systemImage: "flag")
            }
        }

        // Move to Project submenu
        if showProjectMenu {
            Menu {
                ForEach(projects) { project in
                    Button {
                        var updated = task
                        updated.projectId = project.id
                        onUpdate(updated)
                    } label: {
                        HStack {
                            Circle()
                                .fill(project.swiftUIColor)
                                .frame(width: 8, height: 8)
                            Text(project.name)
                        }
                    }
                    .disabled(task.projectId == project.id)
                }
            } label: {
                Label("Move to Project", systemImage: "folder")
            }
        }
    }

    // MARK: - Copy to Clipboard

    private func copyToClipboard() {
        print("[TaskContextMenu] copyToClipboard called")
        print("[TaskContextMenu] - task: '\(task.title)'")
        print("[TaskContextMenu] - subtasks.count: \(subtasks.count)")
        print("[TaskContextMenu] - showSubtasksOption: \(showSubtasksOption)")
        print("[TaskContextMenu] - includeSubtasks: \(includeSubtasks)")

        var parts: [String] = []

        if includeTitle {
            parts.append(task.title)
            print("[TaskContextMenu] - added title")
        }

        if showSubtasksOption && includeSubtasks && !subtasks.isEmpty {
            let subtaskText = subtasks.map { "  - \($0.title)" }.joined(separator: "\n")
            parts.append(subtaskText)
            print("[TaskContextMenu] - added \(subtasks.count) subtasks")
        } else {
            print("[TaskContextMenu] - subtasks NOT added: showSubtasksOption=\(showSubtasksOption), includeSubtasks=\(includeSubtasks), isEmpty=\(subtasks.isEmpty)")
        }

        if includePriority && task.priority != .none {
            parts.append("Priority: \(task.priority.displayName)")
        }

        if includeDueDate, let date = task.dueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append("Due: \(formatter.string(from: date))")
        }

        if includeNotes, let notes = task.notes, !notes.isEmpty {
            parts.append(notes)
        }

        let text = parts.joined(separator: "\n")
        print("[TaskContextMenu] - FINAL copied text:\n\(text)")
        print("[TaskContextMenu] --- END ---")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Simplified Context Menu for Subtasks

/// Simplified context menu for subtasks (no Move to Project, no subtasks option)
struct SubtaskContextMenu: View {
    let task: OmniTask
    let projects: [OmniTaskCore.Project]
    let onUpdate: (OmniTask) -> Void

    var body: some View {
        TaskContextMenu(
            task: task,
            subtasks: [],
            projects: projects,
            onUpdate: onUpdate,
            showSubtasksOption: false,
            showPriorityMenu: true,
            showProjectMenu: false
        )
    }
}

// MARK: - Simplified Context Menu for Completed Tasks

/// Simplified context menu for completed tasks (Copy only)
struct CompletedTaskContextMenu: View {
    let task: OmniTask

    @AppStorage("copyIncludeTitle") private var includeTitle = true
    @AppStorage("copyIncludeNotes") private var includeNotes = true

    var body: some View {
        Menu {
            Toggle("Title", isOn: $includeTitle)
            Toggle("Notes", isOn: $includeNotes)

            Divider()

            Button("Copy") {
                copyToClipboard()
            }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }

    private func copyToClipboard() {
        var parts: [String] = []

        if includeTitle {
            parts.append(task.title)
        }

        if includeNotes, let notes = task.notes, !notes.isEmpty {
            parts.append(notes)
        }

        let text = parts.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
