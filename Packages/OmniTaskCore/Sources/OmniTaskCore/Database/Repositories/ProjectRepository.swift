import Foundation
import GRDB

/// Repository for Project CRUD operations
@MainActor
public final class ProjectRepository: ObservableObject {
    private let database: DatabaseManager
    @Published public private(set) var projects: [Project] = []

    public init(database: DatabaseManager) {
        self.database = database
        loadProjects()
    }

    private func loadProjects() {
        do {
            projects = try database.read { db in
                try Project
                    .filter(Column("isArchived") == false)
                    .order(Column("sortOrder").asc)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load projects: \(error)")
        }
    }

    // MARK: - Default Projects

    public func createDefaultProjectsIfNeeded() async {
        do {
            let count = try await database.asyncRead { db in
                try Project.fetchCount(db)
            }

            if count == 0 {
                let defaultProjects = [
                    Project(name: "Personal", description: "Personal tasks and errands", color: "#10B981", sortOrder: 0),
                    Project(name: "Work", description: "Professional work tasks", color: "#3B82F6", sortOrder: 1),
                    Project(name: "Unsorted", description: "Default for unclear tasks", color: "#6B7280", sortOrder: 999)
                ]

                try await database.asyncWrite { db in
                    for var project in defaultProjects {
                        try project.insert(db)
                    }
                }

                loadProjects()
            }
        } catch {
            print("Failed to create default projects: \(error)")
        }
    }

    // MARK: - Create

    public func create(_ project: Project) async throws {
        try await database.asyncWrite { db in
            var project = project
            try project.insert(db)
        }
        loadProjects()
    }

    // MARK: - Read

    public func fetchAll(includeArchived: Bool = false) async throws -> [Project] {
        try await database.asyncRead { db in
            var request = Project.all()
            if !includeArchived {
                request = request.filter(Column("isArchived") == false)
            }
            return try request.order(Column("sortOrder").asc).fetchAll(db)
        }
    }

    public func fetch(by id: String) async throws -> Project? {
        try await database.asyncRead { db in
            try Project.fetchOne(db, key: id)
        }
    }

    public func fetch(byName name: String) async throws -> Project? {
        try await database.asyncRead { db in
            try Project.filter(Column("name").lowercased == name.lowercased()).fetchOne(db)
        }
    }

    /// Returns project names for AI context
    public func projectNamesWithDescriptions() async throws -> [(name: String, description: String?)] {
        try await database.asyncRead { db in
            try Project
                .filter(Column("isArchived") == false)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
                .map { ($0.name, $0.description) }
        }
    }

    // MARK: - Update

    public func update(_ project: Project) async throws {
        try await database.asyncWrite { db in
            var updatedProject = project
            updatedProject.updatedAt = Date()
            try updatedProject.update(db)
        }
        loadProjects()
    }

    public func archive(_ project: Project) async throws {
        var updated = project
        updated.isArchived = true
        updated.updatedAt = Date()
        try await update(updated)
    }

    public func unarchive(_ project: Project) async throws {
        var updated = project
        updated.isArchived = false
        updated.updatedAt = Date()
        try await update(updated)
    }

    // MARK: - Delete

    public func delete(_ project: Project) async throws {
        _ = try await database.asyncWrite { db in
            try project.delete(db)
        }
        loadProjects()
    }

    // MARK: - Reorder

    public func updateSortOrders(_ projects: [Project]) async throws {
        try await database.asyncWrite { db in
            for var project in projects {
                project.updatedAt = Date()
                try project.update(db)
            }
        }
        loadProjects()
    }

    // MARK: - Helpers

    public func getUnsortedProject() async -> Project? {
        try? await fetch(byName: "Unsorted")
    }

    public func refresh() {
        loadProjects()
    }

    // MARK: - CloudKit Sync Support

    /// Upsert a project from CloudKit sync (insert or update based on existence)
    public func upsertFromCloud(_ project: Project) async throws {
        try await database.asyncWrite { db in
            if try Project.fetchOne(db, key: project.id) != nil {
                // Update existing
                var updatedProject = project
                try updatedProject.update(db)
            } else {
                // Insert new
                var newProject = project
                try newProject.insert(db)
            }
        }
        loadProjects()
    }
}
