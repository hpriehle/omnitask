import SwiftUI

/// Projects management view for Settings
struct ProjectsSettingsView: View {
    @ObservedObject var projectVM: ProjectViewModel
    var tagRepository: TagRepository?
    @State private var editingProject: Project?
    @State private var showingAddProject = false
    @State private var draggingProject: Project?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Projects")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddProject = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Project list with drag and drop
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(projectVM.projects) { project in
                        ProjectSettingsRow(project: project)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(draggingProject?.id == project.id ? Color.accentColor.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingProject = project
                            }
                            .draggable(project.id) {
                                ProjectSettingsRow(project: project)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                            }
                            .dropDestination(for: String.self) { items, _ in
                                guard let droppedId = items.first,
                                      let sourceIndex = projectVM.projects.firstIndex(where: { $0.id == droppedId }),
                                      let destIndex = projectVM.projects.firstIndex(where: { $0.id == project.id }) else {
                                    return false
                                }
                                Task {
                                    await projectVM.reorderProjects(
                                        from: IndexSet(integer: sourceIndex),
                                        to: destIndex > sourceIndex ? destIndex + 1 : destIndex
                                    )
                                }
                                return true
                            }

                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }

            Divider()

            // Footer
            Text("Drag to reorder. Click to edit.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorView(projectVM: projectVM, editingProject: project, tagRepository: tagRepository)
        }
        .sheet(isPresented: $showingAddProject) {
            ProjectEditorView(projectVM: projectVM, tagRepository: tagRepository)
        }
    }
}

/// Row displaying a project in the settings list
struct ProjectSettingsRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: project.color ?? "#6B7280"))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body)

                if let description = project.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    ProjectsSettingsView(
        projectVM: ProjectViewModel(
            projectRepository: ProjectRepository(database: DatabaseManager())
        )
    )
}
