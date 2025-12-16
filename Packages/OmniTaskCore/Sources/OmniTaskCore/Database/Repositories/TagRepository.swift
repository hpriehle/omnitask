import Foundation
import GRDB

/// Repository for Tag CRUD operations
@MainActor
public final class TagRepository: ObservableObject {
    private let database: DatabaseManager
    @Published public private(set) var tags: [Tag] = []

    public init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Create

    public func create(_ tag: Tag) async throws {
        try await database.asyncWrite { db in
            var tag = tag
            try tag.insert(db)
        }
    }

    // MARK: - Read

    public func fetchAll() async throws -> [Tag] {
        try await database.asyncRead { db in
            try Tag.order(Column("name").asc).fetchAll(db)
        }
    }

    public func fetchByProject(_ projectId: String) async throws -> [Tag] {
        try await database.asyncRead { db in
            try Tag
                .filter(Column("projectId") == projectId)
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    public func fetch(by id: String) async throws -> Tag? {
        try await database.asyncRead { db in
            try Tag.fetchOne(db, key: id)
        }
    }

    public func fetchByName(_ name: String, projectId: String) async throws -> Tag? {
        try await database.asyncRead { db in
            try Tag
                .filter(Column("projectId") == projectId)
                .filter(Column("name").lowercased == name.lowercased())
                .fetchOne(db)
        }
    }

    // MARK: - Update

    public func update(_ tag: Tag) async throws {
        try await database.asyncWrite { db in
            var updatedTag = tag
            updatedTag.updatedAt = Date()
            try updatedTag.update(db)
        }
    }

    // MARK: - Delete

    public func delete(_ tag: Tag) async throws {
        _ = try await database.asyncWrite { db in
            try tag.delete(db)
        }
    }

    // MARK: - Task-Tag Operations

    public func addTagToTask(tagId: String, taskId: String) async throws {
        let taskTag = TaskTag(taskId: taskId, tagId: tagId)
        try await database.asyncWrite { db in
            try taskTag.insert(db)
        }
    }

    public func removeTagFromTask(tagId: String, taskId: String) async throws {
        try await database.asyncWrite { db in
            try TaskTag
                .filter(Column("taskId") == taskId)
                .filter(Column("tagId") == tagId)
                .deleteAll(db)
        }
    }

    public func setTagsForTask(taskId: String, tagIds: [String]) async throws {
        try await database.asyncWrite { db in
            // Remove existing tags
            try TaskTag.filter(Column("taskId") == taskId).deleteAll(db)

            // Add new tags
            for tagId in tagIds {
                let taskTag = TaskTag(taskId: taskId, tagId: tagId)
                try taskTag.insert(db)
            }
        }
    }

    public func fetchTagsForTask(_ taskId: String) async throws -> [Tag] {
        try await database.asyncRead { db in
            let tagIds = try TaskTag
                .filter(Column("taskId") == taskId)
                .fetchAll(db)
                .map { $0.tagId }

            guard !tagIds.isEmpty else { return [] }

            return try Tag
                .filter(tagIds.contains(Column("id")))
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    public func fetchTaskIdsForTag(_ tagId: String) async throws -> [String] {
        try await database.asyncRead { db in
            try TaskTag
                .filter(Column("tagId") == tagId)
                .fetchAll(db)
                .map { $0.taskId }
        }
    }
}
