import Foundation
import Combine
import SwiftUI
import OmniTaskCore

/// Dependency container for the iOS app
@MainActor
final class AppEnvironmentiOS: ObservableObject {
    // Database
    let databaseManager: DatabaseManager

    // Repositories
    let taskRepository: TaskRepository
    let projectRepository: ProjectRepository
    let tagRepository: TagRepository

    // Services
    let claudeService: ClaudeService
    let taskStructuringService: TaskStructuringService

    // CloudKit Sync
    let cloudKitSyncService: CloudKitSyncService

    // Settings
    @Published var claudeAPIKey: String {
        didSet {
            UserDefaults.standard.set(claudeAPIKey, forKey: "claudeAPIKey")
            Task {
                await claudeService.updateAPIKey(claudeAPIKey)
            }
        }
    }

    @Published var filterSettings: FilterSortSettings {
        didSet {
            filterSettings.save()
        }
    }

    init() {
        // Initialize database
        self.databaseManager = DatabaseManager()

        // Initialize repositories
        self.taskRepository = TaskRepository(database: databaseManager)
        self.projectRepository = ProjectRepository(database: databaseManager)
        self.tagRepository = TagRepository(database: databaseManager)

        // Load API key from UserDefaults
        let apiKey = UserDefaults.standard.string(forKey: "claudeAPIKey") ?? ""
        self.claudeAPIKey = apiKey

        // Load filter settings from UserDefaults
        self.filterSettings = FilterSortSettings.load()

        // Initialize services
        self.claudeService = ClaudeService(apiKey: apiKey)
        self.taskStructuringService = TaskStructuringService(
            claudeService: claudeService,
            projectRepository: projectRepository
        )

        // Initialize CloudKit sync service
        self.cloudKitSyncService = CloudKitSyncService(
            taskRepository: taskRepository,
            projectRepository: projectRepository
        )

        // Start services
        Task {
            await projectRepository.createDefaultProjectsIfNeeded()
            await cloudKitSyncService.start()
        }
    }
}
