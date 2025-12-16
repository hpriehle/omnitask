import SwiftUI
import OmniTaskCore

/// Expanded view for editing task details
struct TaskDetailView: View {
    @Binding var task: OmniTask
    let projects: [OmniTaskCore.Project]
    var tagRepository: TagRepository?
    let onSave: (OmniTask) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var selectedProjectId: String?
    @State private var priority: Priority
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool
    @State private var isRecurring: Bool
    @State private var recurringPattern: RecurringPattern?

    // Tag state
    @State private var availableTags: [OmniTaskCore.Tag] = []
    @State private var selectedTagIds: Set<String> = []
    @State private var tagSearchText: String = ""
    @State private var showingTagPicker = false

    // Focus state to prevent auto-selection
    @FocusState private var titleFocused: Bool

    init(
        task: Binding<OmniTask>,
        projects: [OmniTaskCore.Project],
        tagRepository: TagRepository? = nil,
        onSave: @escaping (OmniTask) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._task = task
        self.projects = projects
        self.tagRepository = tagRepository
        self.onSave = onSave
        self.onCancel = onCancel

        self._title = State(initialValue: task.wrappedValue.title)
        self._notes = State(initialValue: task.wrappedValue.notes ?? "")
        self._selectedProjectId = State(initialValue: task.wrappedValue.projectId)
        self._priority = State(initialValue: task.wrappedValue.priority)
        self._dueDate = State(initialValue: task.wrappedValue.dueDate)
        self._hasDueDate = State(initialValue: task.wrappedValue.dueDate != nil)
        self._isRecurring = State(initialValue: task.wrappedValue.recurringPattern != nil)
        self._recurringPattern = State(initialValue: task.wrappedValue.recurringPattern)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Subtask indicator (if this is a subtask)
            if task.isSubtask {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Subtask")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Title
            TextField("Task title", text: $title)
                .textFieldStyle(.plain)
                .font(.headline)
                .focused($titleFocused)

            // Project picker
            HStack {
                Text("Project")
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $selectedProjectId) {
                    Text("None").tag(nil as String?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id as String?)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            // Priority picker
            HStack {
                Text("Priority")
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $priority) {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            // Due date
            HStack {
                Toggle("Due date", isOn: $hasDueDate)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Text("Due date")
                    .foregroundColor(.secondary)

                Spacer()

                if hasDueDate {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { dueDate ?? Date() },
                            set: { dueDate = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .fixedSize()
                }
            }

            // Recurring
            if hasDueDate {
                RecurrenceOptionsView(
                    isRecurring: $isRecurring,
                    pattern: $recurringPattern
                )
            }

            // Tags section
            if tagRepository != nil && selectedProjectId != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tags")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showingTagPicker = true
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    // Selected tags
                    if !selectedTagIds.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(availableTags.filter { selectedTagIds.contains($0.id) }) { tag in
                                TaskTagChip(tag: tag) {
                                    selectedTagIds.remove(tag.id)
                                }
                            }
                        }
                    } else {
                        Text("No tags")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .popover(isPresented: $showingTagPicker) {
                    TagPickerView(
                        availableTags: availableTags,
                        selectedTagIds: $selectedTagIds,
                        tagSearchText: $tagSearchText,
                        projectId: selectedProjectId,
                        tagRepository: tagRepository,
                        onTagCreated: { loadTags() }
                    )
                }
            }

            // Notes
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .foregroundColor(.secondary)
                    .font(.caption)

                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 60)
                    .padding(4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
            }

            Spacer()

            // Action buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)

                Spacer()

                Button("Save") {
                    saveTask()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 320, maxWidth: 320, minHeight: 480, maxHeight: 650)
        .onAppear {
            // Prevent auto-selection of title text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFocused = false
            }
            loadTags()
            loadSelectedTags()
        }
        .onChange(of: selectedProjectId) { newProjectId in
            // Reload tags when project changes
            loadTags()
            // Clear selected tags when switching projects
            selectedTagIds.removeAll()
        }
    }

    private func loadTags() {
        guard let projectId = selectedProjectId, let tagRepository = tagRepository else {
            availableTags = []
            return
        }
        Task {
            availableTags = (try? await tagRepository.fetchByProject(projectId)) ?? []
        }
    }

    private func loadSelectedTags() {
        guard let tagRepository = tagRepository else { return }
        Task {
            let tags = (try? await tagRepository.fetchTagsForTask(task.id)) ?? []
            selectedTagIds = Set(tags.map { $0.id })
        }
    }

    private func saveTask() {
        print("[TaskDetailView] saveTask called")
        print("[TaskDetailView] hasDueDate: \(hasDueDate)")
        print("[TaskDetailView] dueDate state: \(dueDate?.description ?? "nil")")

        var updatedTask = task
        updatedTask.title = title
        updatedTask.notes = notes.isEmpty ? nil : notes
        updatedTask.projectId = selectedProjectId
        updatedTask.priority = priority

        // When hasDueDate is enabled but dueDate is nil, use current date
        if hasDueDate {
            updatedTask.dueDate = dueDate ?? Date()
            print("[TaskDetailView] Setting dueDate to: \(updatedTask.dueDate?.description ?? "nil")")
        } else {
            updatedTask.dueDate = nil
            print("[TaskDetailView] Clearing dueDate")
        }

        if isRecurring && hasDueDate {
            updatedTask.recurringPattern = recurringPattern
        } else {
            updatedTask.recurringPattern = nil
        }

        print("[TaskDetailView] Final task dueDate: \(updatedTask.dueDate?.description ?? "nil")")

        // Save tags
        if let tagRepository = tagRepository {
            Task {
                try? await tagRepository.setTagsForTask(taskId: updatedTask.id, tagIds: Array(selectedTagIds))
            }
        }

        print("[TaskDetailView] Calling onSave...")
        onSave(updatedTask)
    }
}

// MARK: - Task Tag Chip (for display in TaskDetailView)

struct TaskTagChip: View {
    let tag: OmniTaskCore.Tag
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.swiftUIColor)
                .frame(width: 6, height: 6)

            Text(tag.name)
                .font(.caption2)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tag.swiftUIColor.opacity(0.15))
        .cornerRadius(10)
    }
}

// MARK: - Tag Picker View

struct TagPickerView: View {
    let availableTags: [OmniTaskCore.Tag]
    @Binding var selectedTagIds: Set<String>
    @Binding var tagSearchText: String
    let projectId: String?
    let tagRepository: TagRepository?
    let onTagCreated: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var filteredTags: [OmniTaskCore.Tag] {
        if tagSearchText.isEmpty {
            return availableTags
        }
        return availableTags.filter { $0.name.localizedCaseInsensitiveContains(tagSearchText) }
    }

    private var canCreateNewTag: Bool {
        guard !tagSearchText.isEmpty else { return false }
        return !availableTags.contains { $0.name.localizedCaseInsensitiveCompare(tagSearchText) == .orderedSame }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search or create tag", text: $tagSearchText)
                    .textFieldStyle(.plain)
                if !tagSearchText.isEmpty {
                    Button {
                        tagSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)

            Divider()

            // Tag list
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Create new tag option
                    if canCreateNewTag {
                        Button {
                            createNewTag()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentColor)
                                Text("Create \"\(tagSearchText)\"")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }

                    // Existing tags
                    ForEach(filteredTags) { tag in
                        Button {
                            toggleTag(tag)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(tag.swiftUIColor)
                                    .frame(width: 10, height: 10)

                                Text(tag.name)
                                    .foregroundColor(.primary)

                                Spacer()

                                if selectedTagIds.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if filteredTags.isEmpty && !canCreateNewTag {
                        Text("No tags found")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }
        }
        .frame(width: 220, height: 200)
    }

    private func toggleTag(_ tag: OmniTaskCore.Tag) {
        if selectedTagIds.contains(tag.id) {
            selectedTagIds.remove(tag.id)
        } else {
            selectedTagIds.insert(tag.id)
        }
    }

    private func createNewTag() {
        guard let projectId = projectId, let tagRepository = tagRepository else { return }
        let newTag = OmniTaskCore.Tag(name: tagSearchText, projectId: projectId)
        Task {
            try? await tagRepository.create(newTag)
            selectedTagIds.insert(newTag.id)
            tagSearchText = ""
            onTagCreated()
        }
    }
}

// MARK: - Preview

#Preview {
    TaskDetailView(
        task: .constant(OmniTask(title: "Test task", priority: .high, dueDate: Date())),
        projects: [
            OmniTaskCore.Project(name: "Work", color: "#3B82F6"),
            OmniTaskCore.Project(name: "Personal", color: "#10B981")
        ],
        onSave: { _ in },
        onCancel: {}
    )
}
