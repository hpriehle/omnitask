import Foundation
import Combine
import SwiftUI

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

    // Monitors
    let pushToTalkMonitor: PushToTalkMonitor

    // UI State
    let expansionState = ExpansionState()

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
        self.speechRecognitionService = SpeechRecognitionService()
        self.urlSchemeHandler = URLSchemeHandler()

        // Initialize monitors
        self.pushToTalkMonitor = PushToTalkMonitor()
    }
}
