import SwiftUI
import KeyboardShortcuts

@main
struct OmniTaskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar apps need at least one scene, but we manage windows manually
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    // Show panel in expanded mode and focus input
                    appDelegate.windowManager.showPanel()
                    appDelegate.windowManager.setExpanded(true)
                    // Post notification to focus the input field
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .focusTaskInput, object: nil)
                    }
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

extension KeyboardShortcuts.Name {
    static let toggleOmniTask = Self("toggleOmniTask")
    static let newSubtask = Self("newSubtask")
    static let completeSelected = Self("completeSelected")
    static let setAsCurrent = Self("setAsCurrent")
    static let navigateUp = Self("navigateUp")
    static let navigateDown = Self("navigateDown")
    static let goToToday = Self("goToToday")
    static let goToAll = Self("goToAll")
}
