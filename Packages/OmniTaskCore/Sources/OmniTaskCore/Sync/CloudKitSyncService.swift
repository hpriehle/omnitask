import Foundation
import CloudKit
import Combine
import os.log

// MARK: - Record Type Constants (outside class to avoid actor isolation)

/// CloudKit record type identifiers
public enum CloudKitRecordType {
    public static let task = "Task"
    public static let project = "Project"
}

/// CloudKit container identifier
public let cloudKitContainerIdentifier = "iCloud.com.harrisonriehle.omnitask"

/// CloudKit sync service using CKSyncEngine (iOS 17+/macOS 14+)
@MainActor
public final class CloudKitSyncService: ObservableObject {
    // MARK: - Published State

    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var syncError: Error?
    @Published public private(set) var pendingChangesCount: Int = 0

    // MARK: - Private Properties

    private let container: CKContainer
    private let database: CKDatabase
    private var syncEngine: CKSyncEngine?
    private let logger = Logger(subsystem: "com.omnitask.app", category: "CloudKitSync")

    // Repositories for database operations
    private weak var taskRepository: TaskRepository?
    private weak var projectRepository: ProjectRepository?

    // MARK: - Initialization

    public init(
        taskRepository: TaskRepository? = nil,
        projectRepository: ProjectRepository? = nil
    ) {
        self.container = CKContainer(identifier: cloudKitContainerIdentifier)
        self.database = container.privateCloudDatabase
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository
    }

    // MARK: - Public Methods

    /// Start the sync engine
    public func start() async {
        logger.info("Starting CloudKit sync service")

        // Check iCloud account status
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                logger.warning("iCloud account not available: \(String(describing: status))")
                return
            }
        } catch {
            logger.error("Failed to check iCloud account status: \(error.localizedDescription)")
            syncError = error
            return
        }

        // Initialize sync engine
        await initializeSyncEngine()
    }

    /// Stop the sync engine
    public func stop() {
        logger.info("Stopping CloudKit sync service")
        syncEngine = nil
    }

    /// Manually trigger a sync
    public func sync() async {
        guard let syncEngine = syncEngine else {
            logger.warning("Sync engine not initialized")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await syncEngine.fetchChanges()
            lastSyncDate = Date()
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
            syncError = error
        }
    }

    /// Queue a record for upload
    public func queueUpload(for recordID: CKRecord.ID) {
        syncEngine?.state.add(pendingRecordZoneChanges: [
            .saveRecord(recordID)
        ])
        updatePendingChangesCount()
    }

    /// Queue a record for deletion
    public func queueDeletion(for recordID: CKRecord.ID) {
        syncEngine?.state.add(pendingRecordZoneChanges: [
            .deleteRecord(recordID)
        ])
        updatePendingChangesCount()
    }

    // MARK: - Private Methods

    private func initializeSyncEngine() async {
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: loadSyncEngineState(),
            delegate: self
        )

        syncEngine = CKSyncEngine(configuration)
        logger.info("Sync engine initialized")
    }

    private func loadSyncEngineState() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: "syncEngineState"),
              let state = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data) else {
            return nil
        }
        return state
    }

    private func saveSyncEngineState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: "syncEngineState")
    }

    private func updatePendingChangesCount() {
        pendingChangesCount = syncEngine?.state.pendingRecordZoneChanges.count ?? 0
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudKitSyncService: CKSyncEngineDelegate {
    nonisolated public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
        Task { @MainActor in
            switch event {
            case .stateUpdate(let update):
                saveSyncEngineState(update.stateSerialization)

            case .accountChange(let event):
                handleAccountChange(event)

            case .fetchedDatabaseChanges(let event):
                handleFetchedDatabaseChanges(event)

            case .fetchedRecordZoneChanges(let event):
                handleFetchedRecordZoneChanges(event)

            case .sentDatabaseChanges(let event):
                handleSentDatabaseChanges(event)

            case .sentRecordZoneChanges(let event):
                handleSentRecordZoneChanges(event)

            case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
                 .didFetchChanges, .willSendChanges, .didSendChanges:
                // Progress events - can be used for UI updates
                break

            @unknown default:
                logger.warning("Unknown sync engine event")
            }
        }
    }

    nonisolated public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // This is called on a background thread
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges

        guard !pendingChanges.isEmpty else { return nil }

        // Process up to 400 changes at a time (CK limit)
        let batch = Array(pendingChanges.prefix(400))

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batch) { recordID in
            // Need to fetch the record to save from our local database
            // This will be called for each record that needs to be saved
            return await self.fetchRecordToSave(for: recordID)
        }
    }

    // MARK: - Event Handlers

    @MainActor
    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
        switch event.changeType {
        case .signIn:
            logger.info("User signed into iCloud")
            Task.detached { @MainActor [weak self] in
                await self?.sync()
            }
        case .signOut:
            logger.info("User signed out of iCloud")
            // Could clear local sync state here
        case .switchAccounts:
            logger.info("iCloud account switched")
            // Need to re-sync everything
            Task.detached { @MainActor [weak self] in
                await self?.sync()
            }
        @unknown default:
            break
        }
    }

    @MainActor
    private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
        // Handle zone deletions if any
        for deletion in event.deletions {
            logger.info("Zone deleted: \(deletion.zoneID.zoneName)")
        }
    }

    @MainActor
    private func handleFetchedRecordZoneChanges(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        // Process fetched records
        for modification in event.modifications {
            let record = modification.record

            switch record.recordType {
            case CloudKitRecordType.task:
                handleFetchedTaskRecord(record)
            case CloudKitRecordType.project:
                handleFetchedProjectRecord(record)
            default:
                logger.warning("Unknown record type: \(record.recordType)")
            }
        }

        // Process deletions
        for deletion in event.deletions {
            handleRecordDeletion(deletion.recordID)
        }

        lastSyncDate = Date()
    }

    @MainActor
    private func handleSentDatabaseChanges(_ event: CKSyncEngine.Event.SentDatabaseChanges) {
        // Handle any database-level changes we sent
    }

    @MainActor
    private func handleSentRecordZoneChanges(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
        // Handle successful saves
        for result in event.savedRecords {
            logger.debug("Record saved: \(result.recordID.recordName)")
        }

        // Handle failed saves
        for failedSave in event.failedRecordSaves {
            let recordID = failedSave.record.recordID
            let error = failedSave.error

            logger.error("Failed to save record \(recordID.recordName): \(error.localizedDescription)")

            // Handle specific error types
            switch error.code {
            case .serverRecordChanged:
                // Conflict - need to resolve
                if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    handleConflict(for: recordID, serverRecord: serverRecord)
                }
            default:
                break
            }
        }

        // Handle successful deletions
        for recordID in event.deletedRecordIDs {
            logger.debug("Record deleted: \(recordID.recordName)")
        }

        updatePendingChangesCount()
    }

    // MARK: - Record Processing

    @MainActor
    private func handleFetchedTaskRecord(_ record: CKRecord) {
        guard let task = OmniTask(from: record) else {
            logger.error("Failed to parse task from CloudKit record")
            return
        }

        // Update local database
        Task {
            do {
                try await taskRepository?.upsertFromCloud(task)
                logger.debug("Task synced from cloud: \(task.title)")
            } catch {
                logger.error("Failed to save synced task: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func handleFetchedProjectRecord(_ record: CKRecord) {
        guard let project = Project(from: record) else {
            logger.error("Failed to parse project from CloudKit record")
            return
        }

        // Update local database
        Task {
            do {
                try await projectRepository?.upsertFromCloud(project)
                logger.debug("Project synced from cloud: \(project.name)")
            } catch {
                logger.error("Failed to save synced project: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func handleRecordDeletion(_ recordID: CKRecord.ID) {
        // Determine record type from recordID and delete locally
        // The recordID.recordName should match our local record ID
        let localID = recordID.recordName

        Task {
            // Try to delete as task first, then project
            // In a real app, you'd want to track record types better
            do {
                if let task = try await taskRepository?.fetch(by: localID) {
                    try await taskRepository?.delete(task)
                    logger.debug("Task deleted from cloud sync: \(localID)")
                }
            } catch {
                // Not a task, try project
                do {
                    if let project = try await projectRepository?.fetch(by: localID) {
                        try await projectRepository?.delete(project)
                        logger.debug("Project deleted from cloud sync: \(localID)")
                    }
                } catch {
                    logger.warning("Could not find record to delete: \(localID)")
                }
            }
        }
    }

    @MainActor
    private func handleConflict(for recordID: CKRecord.ID, serverRecord: CKRecord) {
        logger.info("Resolving conflict for record: \(recordID.recordName)")

        // Get local record and resolve conflict
        // Then re-queue the resolved version for upload
        Task {
            switch serverRecord.recordType {
            case CloudKitRecordType.task:
                if let serverTask = OmniTask(from: serverRecord),
                   let localTask = try await taskRepository?.fetch(by: recordID.recordName) {
                    let resolved = ConflictResolver.shared.resolveTaskConflict(
                        local: localTask,
                        server: serverTask,
                        serverRecord: serverRecord
                    )
                    try await taskRepository?.update(resolved)
                    queueUpload(for: recordID)
                }
            case CloudKitRecordType.project:
                if let serverProject = Project(from: serverRecord),
                   let localProject = try await projectRepository?.fetch(by: recordID.recordName) {
                    let resolved = ConflictResolver.shared.resolveProjectConflict(
                        local: localProject,
                        server: serverProject,
                        serverRecord: serverRecord
                    )
                    try await projectRepository?.update(resolved)
                    queueUpload(for: recordID)
                }
            default:
                break
            }
        }
    }

    // MARK: - Record Fetching

    nonisolated private func fetchRecordToSave(for recordID: CKRecord.ID) async -> CKRecord? {
        // This is called from a background thread
        // Need to safely access our data
        // In a real implementation, you'd need proper thread-safe access to the database

        // For now, return nil and handle record creation elsewhere
        // A proper implementation would use a serial queue or actor for database access
        return nil
    }
}

// MARK: - CloudKit Record Extensions

extension OmniTask {
    /// Initialize from a CloudKit record
    public init?(from record: CKRecord) {
        guard record.recordType == CloudKitRecordType.task,
              let title = record["title"] as? String else {
            return nil
        }

        self.init(
            id: record.recordID.recordName,
            title: title,
            notes: record["notes"] as? String,
            projectId: (record["projectRef"] as? CKRecord.Reference)?.recordID.recordName,
            parentTaskId: (record["parentTaskRef"] as? CKRecord.Reference)?.recordID.recordName,
            priority: Priority(rawValue: (record["priority"] as? Int64).map { Int($0) } ?? Priority.medium.rawValue) ?? .medium,
            dueDate: record["dueDate"] as? Date,
            isCompleted: (record["isCompleted"] as? Int64) == 1,
            completedAt: record["completedAt"] as? Date,
            sortOrder: (record["sortOrder"] as? Int64).map { Int($0) } ?? 0,
            todaySortOrder: (record["todaySortOrder"] as? Int64).map { Int($0) },
            isCurrentTask: (record["isCurrentTask"] as? Int64) == 1,
            recurringPattern: {
                if let json = record["recurringPatternJSON"] as? String,
                   let data = json.data(using: .utf8) {
                    return try? JSONDecoder().decode(RecurringPattern.self, from: data)
                }
                return nil
            }(),
            originalInput: record["originalInput"] as? String,
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        )
    }

    /// Convert to a CloudKit record
    public func toCKRecord(in zoneID: CKRecordZone.ID = .default) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.task, recordID: recordID)

        record["title"] = title
        record["notes"] = notes
        record["priority"] = Int64(priority.rawValue)
        record["dueDate"] = dueDate
        record["isCompleted"] = isCompleted ? 1 : 0 as Int64
        record["completedAt"] = completedAt
        record["sortOrder"] = Int64(sortOrder)
        record["todaySortOrder"] = todaySortOrder.map { Int64($0) }
        record["isCurrentTask"] = isCurrentTask ? 1 : 0 as Int64
        record["originalInput"] = originalInput
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt

        if let projectId = projectId {
            let projectRef = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: projectId, zoneID: zoneID),
                action: .none
            )
            record["projectRef"] = projectRef
        }

        if let parentTaskId = parentTaskId {
            let parentRef = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: parentTaskId, zoneID: zoneID),
                action: .deleteSelf
            )
            record["parentTaskRef"] = parentRef
        }

        if let pattern = recurringPattern,
           let data = try? JSONEncoder().encode(pattern),
           let json = String(data: data, encoding: .utf8) {
            record["recurringPatternJSON"] = json
        }

        return record
    }
}

extension Project {
    /// Initialize from a CloudKit record
    public init?(from record: CKRecord) {
        guard record.recordType == CloudKitRecordType.project,
              let name = record["name"] as? String else {
            return nil
        }

        self.init(
            id: record.recordID.recordName,
            name: name,
            description: record["description"] as? String,
            color: record["color"] as? String,
            sortOrder: (record["sortOrder"] as? Int64).map { Int($0) } ?? 0,
            isArchived: (record["isArchived"] as? Int64) == 1,
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        )
    }

    /// Convert to a CloudKit record
    public func toCKRecord(in zoneID: CKRecordZone.ID = .default) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordType.project, recordID: recordID)

        record["name"] = name
        record["description"] = self.description
        record["color"] = color
        record["sortOrder"] = Int64(sortOrder)
        record["isArchived"] = isArchived ? 1 : 0 as Int64
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt

        return record
    }
}
