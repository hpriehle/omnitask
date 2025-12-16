import Foundation
import Combine
import OmniTaskCore

/// Represents a single toast notification for a created task
struct ToastItem: Identifiable, Equatable {
    let id: String
    let task: OmniTask
    let createdAt: Date

    init(task: OmniTask) {
        self.id = UUID().uuidString
        self.task = task
        self.createdAt = Date()
    }

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages toast notifications for task creation
@MainActor
final class ToastViewModel: ObservableObject {
    @Published private(set) var visibleToasts: [ToastItem] = []
    @Published private(set) var queuedCount: Int = 0

    private var queue: [ToastItem] = []
    private var dismissTimers: [String: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// Unique instance ID for debugging
    private let instanceId = UUID().uuidString.prefix(8)

    /// Track recently shown task IDs to prevent duplicates
    private var recentlyShownTaskIds: Set<String> = []
    private var dedupeCleanupTimer: Task<Void, Never>?

    private let maxVisible: Int = 3
    private let displayDuration: TimeInterval = 3.0
    private let dedupeDuration: TimeInterval = 5.0 // Prevent same task from showing twice within 5 seconds

    init() {
        print("[ToastViewModel:\(instanceId)] init - object: \(ObjectIdentifier(self)) - setting up notification observer")
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        print("[ToastViewModel:\(instanceId)] setupNotificationObserver called")
        NotificationCenter.default.publisher(for: .taskCreated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else {
                    print("[ToastViewModel:DEALLOCATED] Received notification but self is nil")
                    return
                }
                print("[ToastViewModel:\(self.instanceId)] Received .taskCreated notification")
                guard let tasks = notification.userInfo?["tasks"] as? [OmniTask] else {
                    print("[ToastViewModel:\(self.instanceId)] Failed to extract tasks from notification userInfo")
                    return
                }
                print("[ToastViewModel:\(self.instanceId)] Extracted \(tasks.count) task(s) from notification")
                self.addToasts(for: tasks)
            }
            .store(in: &cancellables)
    }

    func addToasts(for tasks: [OmniTask]) {
        print("[ToastViewModel:\(instanceId)] addToasts called with \(tasks.count) task(s)")
        print("[ToastViewModel:\(instanceId)] Current visibleToasts: \(visibleToasts.count), queue: \(queue.count)")
        for task in tasks {
            // Skip if we've recently shown a toast for this task (deduplication)
            guard !recentlyShownTaskIds.contains(task.id) else {
                print("[ToastViewModel] Skipping duplicate toast for task: \(task.title)")
                continue
            }

            // Mark this task as recently shown
            recentlyShownTaskIds.insert(task.id)
            scheduleDedupeCleanup(for: task.id)

            let toast = ToastItem(task: task)

            if visibleToasts.count < maxVisible {
                showToast(toast)
            } else {
                queue.append(toast)
                queuedCount = queue.count
            }
        }
    }

    /// Remove task ID from dedupe set after delay
    private func scheduleDedupeCleanup(for taskId: String) {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(dedupeDuration * 1_000_000_000))
            await MainActor.run {
                self.recentlyShownTaskIds.remove(taskId)
            }
        }
    }

    private func showToast(_ toast: ToastItem) {
        print("[ToastViewModel:\(instanceId)] showToast - adding toast for task: \(toast.task.title)")
        visibleToasts.append(toast)
        print("[ToastViewModel:\(instanceId)] visibleToasts count is now: \(visibleToasts.count)")
        scheduleDismissal(for: toast.id)
    }

    private func scheduleDismissal(for toastId: String) {
        dismissTimers[toastId]?.cancel()

        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(displayDuration * 1_000_000_000))
            await MainActor.run {
                self.dismiss(toastId: toastId)
            }
        }

        dismissTimers[toastId] = timer
    }

    func dismiss(toastId: String) {
        dismissTimers[toastId]?.cancel()
        dismissTimers.removeValue(forKey: toastId)

        visibleToasts.removeAll { $0.id == toastId }

        // Show next queued toast
        if !queue.isEmpty && visibleToasts.count < maxVisible {
            let next = queue.removeFirst()
            queuedCount = queue.count
            showToast(next)
        }
    }

    func dismissAll() {
        for timer in dismissTimers.values {
            timer.cancel()
        }
        dismissTimers.removeAll()
        visibleToasts.removeAll()
        queue.removeAll()
        queuedCount = 0
    }
}
