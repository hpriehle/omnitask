import SwiftUI

/// Lightweight inline subtask row with indentation
struct SubtaskRowView: View {
    let task: OmniTask
    let projects: [Project]
    var tagRepository: TagRepository?
    let onComplete: () -> Void
    let onUpdate: (OmniTask) -> Void
    let onDelete: () -> Void

    // Keyboard navigation
    var isKeyboardSelected: Bool = false

    @State private var isHovered = false
    @State private var isCompleting = false
    @State private var showingDetail = false
    @State private var editableTask: OmniTask

    init(
        task: OmniTask,
        projects: [Project],
        tagRepository: TagRepository? = nil,
        onComplete: @escaping () -> Void,
        onUpdate: @escaping (OmniTask) -> Void,
        onDelete: @escaping () -> Void,
        isKeyboardSelected: Bool = false
    ) {
        self.task = task
        self.projects = projects
        self.tagRepository = tagRepository
        self.onComplete = onComplete
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.isKeyboardSelected = isKeyboardSelected
        self._editableTask = State(initialValue: task)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Checkbox
            Button(action: completeWithAnimation) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(task.isCompleted ? .green : .secondary)
                    .scaleEffect(isCompleting ? 1.2 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)

            // Title with marquee scroll on hover for long titles
            GeometryReader { geo in
                MarqueeText(
                    text: task.title,
                    font: .system(size: 13),
                    containerWidth: geo.size.width,
                    isHovered: $isHovered
                )
                .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
            }
            .frame(height: 16)
            .strikethrough(task.isCompleted)
        }
        .padding(.leading, 36) // Indent - checkbox aligns under parent title
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isKeyboardSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.05) : Color.clear))
        }
        .overlay {
            if isKeyboardSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editableTask = task
            showingDetail = true
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .opacity(isCompleting ? 0.5 : 1.0)
        .sheet(isPresented: $showingDetail) {
            TaskDetailView(
                task: $editableTask,
                projects: projects,
                tagRepository: tagRepository,
                onSave: { updatedTask in
                    onUpdate(updatedTask)
                    showingDetail = false
                },
                onCancel: {
                    showingDetail = false
                }
            )
        }
    }

    // MARK: - Actions

    private func completeWithAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isCompleting = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onComplete()
        }
    }
}

// MARK: - Inline Subtask Input

/// Inline text field for quickly adding subtasks
struct InlineSubtaskInput: View {
    let parentId: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Empty checkbox placeholder
            Image(systemName: "circle")
                .font(.system(size: 16))
                .foregroundColor(.secondary.opacity(0.5))

            // Text field
            TextField("Add subtask...", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit {
                    submitIfValid()
                }
                .onExitCommand {
                    onCancel()
                }

            // Confirm button
            Button {
                submitIfValid()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(title.isEmpty ? .secondary.opacity(0.5) : .green)
            }
            .buttonStyle(.plain)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Cancel button
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 36) // Indent - matches subtask rows
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        }
        .onAppear {
            isFocused = true
        }
    }

    private func submitIfValid() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onSubmit(trimmed)
        } else {
            onCancel()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 4) {
        SubtaskRowView(
            task: OmniTask(
                title: "Book flights to Paris",
                parentTaskId: "parent-123",
                priority: .medium
            ),
            projects: [],
            onComplete: {},
            onUpdate: { _ in },
            onDelete: {}
        )

        SubtaskRowView(
            task: OmniTask(
                title: "This is a very long subtask title that should scroll when hovered over",
                parentTaskId: "parent-123",
                priority: .medium
            ),
            projects: [],
            onComplete: {},
            onUpdate: { _ in },
            onDelete: {}
        )

        SubtaskRowView(
            task: OmniTask(
                title: "Reserve hotel",
                parentTaskId: "parent-123",
                priority: .medium,
                isCompleted: true,
                completedAt: Date()
            ),
            projects: [],
            onComplete: {},
            onUpdate: { _ in },
            onDelete: {}
        )

        InlineSubtaskInput(
            parentId: "parent-123",
            onSubmit: { _ in },
            onCancel: {}
        )
    }
    .padding()
    .frame(width: 320)
}
