import Foundation
import Combine
import SwiftUI
import Sparkle
import OmniTaskCore

/// Observable state for expansion anchor, shared between WindowManager and SwiftUI views
@MainActor
final class ExpansionState: ObservableObject {
    @Published var anchor: ExpansionAnchor = .topLeft
}

/// Dependency container for the app
@MainActor
final class AppEnvironment: ObservableObject {
    // Database
    let databaseManager: DatabaseManager

    // Repositories
    let taskRepository: TaskRepository
    let projectRepository: ProjectRepository
    let tagRepository: TagRepository

    // Services
    let claudeService: ClaudeService
    let taskStructuringService: TaskStructuringService
    let speechRecognitionService: SpeechRecognitionService
    let urlSchemeHandler: URLSchemeHandler

    // CloudKit Sync
    let cloudKitSyncService: CloudKitSyncService

    // Monitors
    let pushToTalkMonitor: PushToTalkMonitor

    // UI State
    let expansionState = ExpansionState()

    // Sparkle Updater
    let updaterController: SPUStandardUpdaterController

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

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
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

        // Load onboarding state
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        // Initialize services
        self.claudeService = ClaudeService(apiKey: apiKey)
        self.taskStructuringService = TaskStructuringService(
            claudeService: claudeService,
            projectRepository: projectRepository
        )
        self.speechRecognitionService = SpeechRecognitionService()
        self.urlSchemeHandler = URLSchemeHandler()

        // Initialize CloudKit sync service with OmniTaskCore repositories
        self.cloudKitSyncService = CloudKitSyncService(
            taskRepository: taskRepository,
            projectRepository: projectRepository
        )

        // Initialize monitors
        self.pushToTalkMonitor = PushToTalkMonitor()

        // Initialize Sparkle updater
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Start services
        Task {
            await projectRepository.createDefaultProjectsIfNeeded()
            await cloudKitSyncService.start()
        }
    }
}
