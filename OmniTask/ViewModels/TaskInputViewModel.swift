import Foundation
import Combine

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
            let tasks = try await taskStructuringService.parseInput(input)

            // Create tasks in database
            try await taskRepository.createMultiple(tasks)

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

    func createManualTask(task: OmniTask) async {
        do {
            try await taskRepository.create(task)
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
