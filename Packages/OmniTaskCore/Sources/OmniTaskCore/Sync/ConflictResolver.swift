import Foundation
import CloudKit

/// Strategies for resolving sync conflicts
public enum ConflictResolutionStrategy {
    /// Most recent change wins based on timestamp
    case lastWriteWins
    /// Local changes always win
    case localWins
    /// Server changes always win
    case serverWins
    /// Custom merge function
    case custom((Any, Any) -> Any)
}

/// Resolves conflicts between local and server records
public final class ConflictResolver {
    public static let shared = ConflictResolver()

    private init() {}

    /// Resolve conflict between local and server OmniTask records
    /// Default strategy: last write wins, with special rules for certain fields
    public func resolveTaskConflict(
        local: OmniTask,
        server: OmniTask,
        serverRecord: CKRecord
    ) -> OmniTask {
        // Rule 1: If either is completed, completed wins (can't uncomplete from conflict)
        if local.isCompleted || server.isCompleted {
            var resolved = local.updatedAt > server.updatedAt ? local : server
            resolved.isCompleted = local.isCompleted || server.isCompleted
            if resolved.isCompleted && resolved.completedAt == nil {
                resolved.completedAt = local.completedAt ?? server.completedAt ?? Date()
            }
            return resolved
        }

        // Rule 2: For other fields, last write wins
        if local.updatedAt > server.updatedAt {
            return local
        } else {
            return server
        }
    }

    /// Resolve conflict between local and server Project records
    public func resolveProjectConflict(
        local: Project,
        server: Project,
        serverRecord: CKRecord
    ) -> Project {
        // Last write wins
        if local.updatedAt > server.updatedAt {
            return local
        } else {
            return server
        }
    }
}
