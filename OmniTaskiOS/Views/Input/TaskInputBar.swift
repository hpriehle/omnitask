import SwiftUI
import Speech
import OmniTaskCore

/// Bottom input bar for quick task creation with voice support
struct TaskInputBar: View {
    @EnvironmentObject var environment: AppEnvironmentiOS
    @EnvironmentObject var taskRepository: TaskRepository
    @EnvironmentObject var projectRepository: ProjectRepository

    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var isRecording = false
    @State private var audioLevel: Float = 0
    @State private var showingManualEntry = false
    @State private var showingError = false
    @State private var errorMessage: String?

    // Speech recognition
    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("What do you need to do?", text: $inputText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .disabled(isProcessing || isRecording)
                .submitLabel(.send)
                .onSubmit {
                    processInput()
                }

            // Status/Action buttons
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            } else if isRecording {
                // Recording indicator - tap to stop
                Button {
                    stopRecording()
                } label: {
                    VoiceWaveform(audioLevel: audioLevel)
                        .frame(width: 32, height: 24)
                }
                .buttonStyle(.plain)
            } else {
                // Microphone button
                Button {
                    startRecording()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                // Manual entry button
                Button {
                    showingManualEntry = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isRecording ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        }
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .sheet(isPresented: $showingManualEntry) {
            TaskInputSheet()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    // MARK: - Task Processing

    private func processInput() {
        guard !inputText.isEmpty else { return }

        isProcessing = true
        let text = inputText
        inputText = ""

        Task {
            do {
                let tasks = try await environment.taskStructuringService.parseInput(
                    text,
                    defaultToToday: true,
                    defaultProjectId: nil
                )

                for task in tasks {
                    try await taskRepository.create(task)
                }
            } catch {
                // Fallback to simple task creation
                let simpleTask = OmniTask(title: text)
                try? await taskRepository.create(simpleTask)
            }

            isProcessing = false
        }
    }

    // MARK: - Voice Recording

    private func startRecording() {
        // Request permission first
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self.beginRecording()
                case .denied, .restricted:
                    self.errorMessage = "Speech recognition is not authorized. Please enable it in Settings."
                    self.showingError = true
                case .notDetermined:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func beginRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available"
            showingError = true
            return
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session for iOS
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to configure audio session"
            showingError = true
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.inputText = result.bestTranscription.formattedString
            }

            if error != nil || (result?.isFinal ?? false) {
                self.stopRecordingInternal()
            }
        }

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
            self.calculateAudioLevel(buffer: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "Failed to start audio recording"
            showingError = true
        }
    }

    private func stopRecording() {
        stopRecordingInternal()

        // Process the transcribed text
        if !inputText.isEmpty {
            processInput()
        }
    }

    private func stopRecordingInternal() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        audioLevel = 0

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let normalizedLevel = min(rms * 3, 1.0)

        DispatchQueue.main.async {
            self.audioLevel = self.audioLevel * 0.3 + normalizedLevel * 0.7
        }
    }
}

// MARK: - Voice Waveform

struct VoiceWaveform: View {
    let audioLevel: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        .easeInOut(duration: 0.1).delay(Double(index) * 0.02),
                        value: audioLevel
                    )
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 6
        let maxHeight: CGFloat = 24

        // Create wave effect based on audio level
        let offset = sin(Double(index) * 0.5) * 0.3 + 0.7
        let height = baseHeight + (maxHeight - baseHeight) * CGFloat(audioLevel) * CGFloat(offset)

        return max(baseHeight, min(maxHeight, height))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        TaskInputBar()
            .padding()
    }
    .environmentObject(AppEnvironmentiOS())
}
