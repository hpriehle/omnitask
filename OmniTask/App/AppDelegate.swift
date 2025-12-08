import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    lazy var windowManager = WindowManager(environment: environment)
    private var statusItem: NSStatusItem?
    private var confettiController: ConfettiWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] ========================================")
        print("[AppDelegate] Application did finish launching")

        // Set shared instance for global access
        WindowManager.shared = windowManager
        print("[AppDelegate] WindowManager.shared set")

        print("[AppDelegate] Setting up menu bar item...")
        setupMenuBarItem()
        print("[AppDelegate] Setting up keyboard shortcuts...")
        setupKeyboardShortcuts()
        print("[AppDelegate] Showing panel...")
        windowManager.showPanel()
        print("[AppDelegate] Setting up notification observers...")
        setupNotificationObservers()
        print("[AppDelegate] Initializing confetti controller...")
        confettiController = ConfettiWindowController.shared
        print("[AppDelegate] App startup complete")
        print("[AppDelegate] ========================================")

        // Initialize database with default projects
        Task {
            print("[AppDelegate] Creating default projects...")
            await environment.projectRepository.createDefaultProjectsIfNeeded()
            print("[AppDelegate] Default projects initialized")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        print("[AppDelegate] applicationShouldTerminateAfterLastWindowClosed called, returning false")
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        print("[AppDelegate] Opening URLs: \(urls)")
        for url in urls {
            environment.urlSchemeHandler.handle(url: url)
        }
    }

    private func setupMenuBarItem() {
        print("[AppDelegate] Creating status bar item...")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            print("[AppDelegate] ERROR: Failed to get status item button!")
            return
        }

        button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "OmniTask")
        print("[AppDelegate] Status button image set")

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show OmniTask", action: #selector(showApp), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        print("[AppDelegate] Added 'Show OmniTask' menu item")

        menu.addItem(NSMenuItem.separator())

        let hideHourItem = NSMenuItem(title: "Hide for 1 Hour", action: #selector(hideForOneHour), keyEquivalent: "")
        hideHourItem.target = self
        menu.addItem(hideHourItem)
        print("[AppDelegate] Added 'Hide for 1 Hour' menu item")

        let hideMorningItem = NSMenuItem(title: "Hide Until Morning", action: #selector(hideUntilMorning), keyEquivalent: "")
        hideMorningItem.target = self
        menu.addItem(hideMorningItem)
        print("[AppDelegate] Added 'Hide Until Morning' menu item")

        menu.addItem(NSMenuItem.separator())

        let resetPositionItem = NSMenuItem(title: "Reset Pill Position", action: #selector(resetPosition), keyEquivalent: "")
        resetPositionItem.target = self
        menu.addItem(resetPositionItem)
        print("[AppDelegate] Added 'Reset Pill Position' menu item")

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit OmniTask", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        print("[AppDelegate] Added 'Quit' menu item")

        statusItem?.menu = menu
        print("[AppDelegate] Menu attached with \(menu.items.count) items")
        print("[AppDelegate] Menu bar setup complete")
    }

    private func setupKeyboardShortcuts() {
        print("[AppDelegate] Checking for existing keyboard shortcut...")
        if KeyboardShortcuts.getShortcut(for: .toggleOmniTask) == nil {
            print("[AppDelegate] No shortcut set, setting default Cmd+Shift+T")
            KeyboardShortcuts.setShortcut(.init(.t, modifiers: [.command, .shift]), for: .toggleOmniTask)
        } else {
            print("[AppDelegate] Existing shortcut found")
        }

        KeyboardShortcuts.onKeyUp(for: .toggleOmniTask) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                print("[AppDelegate] Keyboard shortcut triggered")
                // Shortcut toggles between collapsed pill and expanded view
                // The pill should always be visible - use menu bar to hide temporarily
                if !self.windowManager.isVisible {
                    // If somehow hidden, show it first
                    print("[AppDelegate] Panel was hidden - showing")
                    self.windowManager.showPanel()
                }
                print("[AppDelegate] Toggling expanded state: \(self.windowManager.isExpanded) -> \(!self.windowManager.isExpanded)")
                self.windowManager.toggleExpanded()
            }
        }
        print("[AppDelegate] Keyboard shortcuts configured")
    }

    @objc private func showApp() {
        print("[AppDelegate] showApp() called")
        windowManager.showPanel()
    }

    @objc private func hideForOneHour() {
        print("[AppDelegate] hideForOneHour() called")
        windowManager.hidePanel(for: 60 * 60)
    }

    @objc private func hideUntilMorning() {
        print("[AppDelegate] hideUntilMorning() called")
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 8
        components.minute = 0

        var targetDate = calendar.date(from: components) ?? now
        if targetDate <= now {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? now
        }

        let interval = targetDate.timeIntervalSince(now)
        print("[AppDelegate] Hiding until \(targetDate) (\(interval) seconds)")
        windowManager.hidePanel(for: interval)
    }

    @objc private func resetPosition() {
        print("[AppDelegate] resetPosition() called")
        windowManager.resetPosition()
        windowManager.showPanel()
    }

    @objc private func quitApp() {
        print("[AppDelegate] quitApp() called - terminating")
        NSApp.terminate(nil)
    }

    // MARK: - Notification Handling

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHidePillRequest(_:)),
            name: .hidePillRequested,
            object: nil
        )
    }

    @objc private func handleHidePillRequest(_ notification: Notification) {
        print("[AppDelegate] handleHidePillRequest received")
        let duration = notification.userInfo?["duration"] as? TimeInterval
        print("[AppDelegate] Hide duration: \(duration ?? -1)")
        windowManager.hidePanel(for: duration)
    }
}
