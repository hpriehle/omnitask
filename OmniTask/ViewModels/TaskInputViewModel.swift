import Foundation
import Combine
import OmniTaskCore

/// ViewModel for task input (text and voice)
@MainActor
final class TaskInputViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var isProcessing = false
    @Published var isRecording = false
    @Published var audioLevel: Float = 0
    @Published var showSuccess = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showNoAPIKeyError = false

    /// When true, tasks default to due today (used during onboarding)
    var isOnboarding = false

    /// Current view context - nil = Today, "all" = All, UUID = specific project
    var currentViewProjectId: String?

    private let taskStructuringService: TaskStructuringService
    private let taskRepository: TaskRepository
    private let speechService: SpeechRecognitionService
    private let pushToTalkMonitor: PushToTalkMonitor

    private var cancellables = Set<AnyCancellable>()

    init(
        taskStructuringService: TaskStructuringService,
        taskRepository: TaskRepository,
        speechService: SpeechRecognitionService,
        pushToTalkMonitor: PushToTalkMonitor
    ) {
        self.taskStructuringService = taskStructuringService
        self.taskRepository = taskRepository
        self.speechService = speechService
        self.pushToTalkMonitor = pushToTalkMonitor

        setupPushToTalk()
    }

    private func setupPushToTalk() {
        pushToTalkMonitor.$isOptionPressed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPressed in
                Task { await self?.handleOptionKey(isPressed: isPressed) }
            }
            .store(in: &cancellables)

        speechService.$transcription
            .receive(on: DispatchQueue.main)
            .assign(to: &$inputText)

        speechService.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        speechService.$audioLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)
    }

    private func handleOptionKey(isPressed: Bool) async {
        if isPressed && !isRecording {
            await startRecording()
        } else if !isPressed && isRecording {
            await stopRecordingAndProcess()
        }
    }

    // MARK: - Text Input

    func submitText() async {
        guard !inputText.isEmpty else { return }

        let text = inputText
        inputText = ""

        await processInput(text)
    }

    // MARK: - Voice Input

    func startRecording() async {
        do {
            try await speechService.startRecording()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func stopRecordingAndProcess() async {
        let transcription = await speechService.stopRecording()

        if !transcription.isEmpty {
            await processInput(transcription)
        }
    }

    // MARK: - Processing

    private func processInput(_ input: String) async {
        isProcessing = true
        errorMessage = nil

        do {
            // Determine defaults based on current view context
            // Today view (nil): default due date to today
            // All view ("all"): no default due date
            // Project view (UUID): assign to that project, no default due date
            let shouldDefaultToToday = isOnboarding || currentViewProjectId == nil
            let defaultProjectId: String? = {
                guard let projectId = currentViewProjectId,
                      projectId != "all" else { return nil }
                return projectId
            }()

            let tasks = try await taskStructuringService.parseInput(
                input,
                defaultToToday: shouldDefaultToToday,
                defaultProjectId: defaultProjectId
            )

            // Create tasks in database
            try await taskRepository.createMultiple(tasks)

            // Post notification for toast display
            NotificationCenter.default.post(
                name: .taskCreated,
                object: nil,
                userInfo: ["tasks": tasks]
            )

            // Clear input on success
            inputText = ""

            // Show success state
            isProcessing = false
            showSuccess = true

            // Reset success after delay
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            showSuccess = false
        } catch {
            isProcessing = false
            showError(error.localizedDescription)
        }
    }

    // MARK: - Manual Task Creation

    func createManualTask(task: OmniTaskCore.OmniTask) async {
        do {
            try await taskRepository.create(task)

            // Post notification for toast display
            NotificationCenter.default.post(
                name: .taskCreated,
                object: nil,
                userInfo: ["tasks": [task]]
            )
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func showError(_ message: String) {
        print("[TaskInputViewModel] showError: \(message)")
        // Check if this is a "no API key" error
        if message.lowercased().contains("no api key") || message.lowercased().contains("no claude api key") {
            print("[TaskInputViewModel] Detected no API key error")
            showNoAPIKeyError = true
        } else {
            errorMessage = message
            showError = true
        }
    }

    func dismissNoAPIKeyError() {
        showNoAPIKeyError = false
    }

    func startMonitoring() {
        pushToTalkMonitor.startMonitoring()
    }

    func stopMonitoring() {
        pushToTalkMonitor.stopMonitoring()
    }

    var placeholder: String {
        "Type or hold \u{2325} to speak..."
    }
}
