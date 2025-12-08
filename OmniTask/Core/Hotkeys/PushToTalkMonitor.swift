import AppKit
import Combine

/// Monitors the Option key for push-to-talk voice input
@MainActor
final class PushToTalkMonitor: ObservableObject {
    @Published private(set) var isOptionPressed = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isMonitoring = false

    nonisolated func cleanup() {
        Task { @MainActor in
            stopMonitoring()
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Global monitor (when app is not focused)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        // Local monitor (when app is focused)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
    }

    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        isMonitoring = false
        isOptionPressed = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let optionPressed = event.modifierFlags.contains(.option)
        if optionPressed != isOptionPressed {
            isOptionPressed = optionPressed
        }
    }
}
