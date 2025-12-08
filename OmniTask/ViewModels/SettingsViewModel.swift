import Foundation
import KeyboardShortcuts

/// ViewModel for app settings
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var claudeAPIKey: String {
        didSet {
            UserDefaults.standard.set(claudeAPIKey, forKey: "claudeAPIKey")
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            // Note: Actual launch at login requires additional setup with SMAppService
        }
    }

    @Published var showAPIKeyField = false

    init() {
        self.claudeAPIKey = UserDefaults.standard.string(forKey: "claudeAPIKey") ?? ""
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    }

    // MARK: - API Key

    var hasAPIKey: Bool {
        !claudeAPIKey.isEmpty
    }

    var maskedAPIKey: String {
        guard !claudeAPIKey.isEmpty else { return "" }
        let prefix = String(claudeAPIKey.prefix(8))
        let suffix = String(claudeAPIKey.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    func testAPIKey() async -> Bool {
        // Simple validation - just check format
        claudeAPIKey.hasPrefix("sk-ant-")
    }

    // MARK: - Keyboard Shortcuts

    var toggleShortcut: KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: .toggleOmniTask)
    }

    func setToggleShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        if let shortcut = shortcut {
            KeyboardShortcuts.setShortcut(shortcut, for: .toggleOmniTask)
        } else {
            KeyboardShortcuts.reset(.toggleOmniTask)
        }
    }

    // MARK: - Data Management

    func exportTasks() async -> URL? {
        // Implementation for exporting tasks to JSON
        nil
    }

    func clearAllData() async {
        // Implementation for clearing all data
    }
}
