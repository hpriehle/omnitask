import SwiftUI
import OmniTaskCore

@main
struct OmniTaskiOSApp: App {
    @StateObject private var environment = AppEnvironmentiOS()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(environment)
                .environmentObject(environment.taskRepository)
                .environmentObject(environment.projectRepository)
        }
    }
}
