import Foundation
import CloudKit

/// Protocol for records that can be synced with CloudKit
public protocol SyncableRecord {
    /// The CloudKit record type name
    static var recordType: CKRecord.RecordType { get }

    /// Convert to CloudKit record
    func toCKRecord() -> CKRecord

    /// Initialize from CloudKit record
    init?(from record: CKRecord)

    /// The unique identifier for this record
    var id: String { get }

    /// When this record was last modified locally
    var updatedAt: Date { get }
}

/// Sync status for local records
public enum SyncStatus: Int, Codable {
    case synced = 0
    case pendingUpload = 1
    case pendingDelete = 2
    case conflict = 3
}

/// Metadata for sync tracking
public struct SyncMetadata: Codable {
    public var cloudKitRecordName: String?
    public var cloudKitChangeTag: String?
    public var syncStatus: SyncStatus
    public var deviceModifiedAt: Date
    public var deletedAt: Date?

    public init(
        cloudKitRecordName: String? = nil,
        cloudKitChangeTag: String? = nil,
        syncStatus: SyncStatus = .pendingUpload,
        deviceModifiedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.cloudKitRecordName = cloudKitRecordName
        self.cloudKitChangeTag = cloudKitChangeTag
        self.syncStatus = syncStatus
        self.deviceModifiedAt = deviceModifiedAt
        self.deletedAt = deletedAt
    }
}
