import SwiftUI
import OmniTaskCore

/// Sheet for creating or editing a project
struct ProjectEditorView: View {
    @ObservedObject var projectVM: ProjectViewModel
    var editingProject: OmniTaskCore.Project?
    var tagRepository: TagRepository?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedColor: String = "#3B82F6"

    // Tag management (using OmniTaskCore.Tag for compatibility with TagRepository)
    @State private var tags: [OmniTaskCore.Tag] = []
    @State private var newTagName: String = ""
    @State private var newTagColor: String = "#6B7280"
    @State private var showingAddTag = false

    private let colorOptions = [
        "#EF4444", // Red
        "#F97316", // Orange
        "#F59E0B", // Amber
        "#EAB308", // Yellow
        "#84CC16", // Lime
        "#22C55E", // Green
        "#10B981", // Emerald
        "#14B8A6", // Teal
        "#06B6D4", // Cyan
        "#0EA5E9", // Sky
        "#3B82F6", // Blue
        "#6366F1", // Indigo
        "#8B5CF6", // Violet
        "#A855F7", // Purple
        "#D946EF", // Fuchsia
        "#EC4899", // Pink
    ]

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(editingProject == nil ? "New Project" : "Edit Project")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            // Name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Description field
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Helps AI assign tasks to this project", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 8), spacing: 8) {
                    ForEach(colorOptions, id: \.self) { color in
                        ColorSwatch(
                            color: color,
                            isSelected: selectedColor == color
                        ) {
                            selectedColor = color
                        }
                    }
                }
            }

            // Tags section (only for existing projects)
            if editingProject != nil, tagRepository != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tags")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showingAddTag = true
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }

                    if tags.isEmpty {
                        Text("No tags yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(tags) { tag in
                                TagChip(tag: tag) {
                                    deleteTag(tag)
                                }
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingAddTag) {
                    AddTagSheet(
                        colorOptions: colorOptions,
                        onAdd: { tagName, tagColor in
                            addTag(name: tagName, color: tagColor)
                        }
                    )
                }
            }

            Spacer()

            // Save button
            Button {
                saveProject()
            } label: {
                Text(editingProject == nil ? "Create Project" : "Save Changes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.isEmpty)

            // Delete button (only for existing projects)
            if let project = editingProject, project.name != "Unsorted" {
                Button(role: .destructive) {
                    Task {
                        await projectVM.deleteProject(project)
                        dismiss()
                    }
                } label: {
                    Text("Delete Project")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 300, height: editingProject != nil ? 480 : 380)
        .onAppear {
            if let project = editingProject {
                name = project.name
                description = project.description ?? ""
                selectedColor = project.color ?? "#3B82F6"
                loadTags()
            }
        }
    }

    private func loadTags() {
        guard let project = editingProject, let tagRepository = tagRepository else { return }
        Task {
            tags = (try? await tagRepository.fetchByProject(project.id)) ?? []
        }
    }

    private func addTag(name: String, color: String) {
        guard let project = editingProject, let tagRepository = tagRepository else { return }
        let tag = OmniTaskCore.Tag(name: name, color: color, projectId: project.id)
        Task {
            try? await tagRepository.create(tag)
            loadTags()
        }
    }

    private func deleteTag(_ tag: OmniTaskCore.Tag) {
        guard let tagRepository = tagRepository else { return }
        Task {
            try? await tagRepository.delete(tag)
            loadTags()
        }
    }

    private func saveProject() {
        Task {
            if var project = editingProject {
                project.name = name
                project.description = description.isEmpty ? nil : description
                project.color = selectedColor
                await projectVM.updateProject(project)
            } else {
                await projectVM.createProject(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    color: selectedColor
                )
            }
            dismiss()
        }
    }
}

/// Color swatch button
struct ColorSwatch: View {
    let color: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: color))
                .frame(width: 24, height: 24)
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(.white, lineWidth: 2)
                            .frame(width: 16, height: 16)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.primary : Color.clear,
                            lineWidth: 2
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: OmniTaskCore.Tag
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.swiftUIColor)
                .frame(width: 8, height: 8)

            Text(tag.name)
                .font(.caption)

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tag.swiftUIColor.opacity(0.15))
        .cornerRadius(12)
    }
}

// MARK: - Add Tag Sheet

struct AddTagSheet: View {
    let colorOptions: [String]
    let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tagName: String = ""
    @State private var selectedColor: String = "#6B7280"

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("New Tag")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            TextField("Tag name", text: $tagName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 8), spacing: 8) {
                    ForEach(colorOptions, id: \.self) { color in
                        ColorSwatch(
                            color: color,
                            isSelected: selectedColor == color
                        ) {
                            selectedColor = color
                        }
                    }
                }
            }

            Spacer()

            Button {
                onAdd(tagName, selectedColor)
                dismiss()
            } label: {
                Text("Add Tag")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(tagName.isEmpty)
        }
        .padding()
        .frame(width: 280, height: 260)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Preview

#Preview("New Project") {
    ProjectEditorView(
        projectVM: ProjectViewModel(
            projectRepository: ProjectRepository(database: DatabaseManager())
        )
    )
}

#Preview("Edit Project") {
    ProjectEditorView(
        projectVM: ProjectViewModel(
            projectRepository: ProjectRepository(database: DatabaseManager())
        ),
        editingProject: OmniTaskCore.Project(name: "Work", description: "Work tasks", color: "#3B82F6")
    )
}
