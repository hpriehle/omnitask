import Foundation
import Combine

/// ViewModel for project management
@MainActor
final class ProjectViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selectedProjectId: String? // nil = Today view
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false

    private let projectRepository: ProjectRepository
    private var cancellables = Set<AnyCancellable>()

    init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository

        projectRepository.$projects
            .receive(on: DispatchQueue.main)
            .assign(to: &$projects)
    }

    // MARK: - Selection

    func selectProject(_ project: Project?) {
        selectedProjectId = project?.id
    }

    func selectToday() {
        selectedProjectId = nil
    }

    func selectAll() {
        selectedProjectId = "all"
    }

    /// Select a project by its index (0-based, excludes Today and All)
    /// Index 0 = first project, Index 1 = second project, etc.
    func selectProjectByIndex(_ index: Int) {
        guard index >= 0 && index < projects.count else { return }
        selectedProjectId = projects[index].id
    }

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectId }
    }

    // MARK: - CRUD Operations

    func createProject(name: String, description: String?, color: String?) async {
        let project = Project(
            name: name,
            description: description,
            color: color,
            sortOrder: projects.count
        )

        do {
            try await projectRepository.create(project)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func updateProject(_ project: Project) async {
        do {
            try await projectRepository.update(project)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func archiveProject(_ project: Project) async {
        do {
            try await projectRepository.archive(project)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func deleteProject(_ project: Project) async {
        do {
            try await projectRepository.delete(project)

            // If the deleted project was selected, switch to Today
            if selectedProjectId == project.id {
                selectToday()
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func reorderProjects(from source: IndexSet, to destination: Int) async {
        var reordered = projects
        reordered.move(fromOffsets: source, toOffset: destination)

        // Update sort orders, keeping Unsorted at 999
        var updatedProjects: [Project] = []
        for (index, var project) in reordered.enumerated() {
            if project.name == "Unsorted" {
                project.sortOrder = 999
            } else {
                project.sortOrder = index
            }
            updatedProjects.append(project)
        }

        do {
            try await projectRepository.updateSortOrders(updatedProjects)
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - Onboarding

    /// Create default projects for onboarding if none exist
    func createDefaultProjectsForOnboarding() async {
        await projectRepository.createDefaultProjectsIfNeeded()
    }

    // MARK: - Helpers

    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }

    func refresh() {
        projectRepository.refresh()
    }
}
