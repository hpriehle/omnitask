import Foundation
import Speech
import AVFoundation
import CoreAudio

/// Service for voice-to-text using Apple's Speech framework
@MainActor
final class SpeechRecognitionService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcription = ""
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published private(set) var audioLevel: Float = 0

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    /// Flag to track when we're intentionally stopping (vs error/auto-stop)
    private var isIntentionallyStopping = false
    /// Stores the last valid transcription to prevent overwrites from cancel callbacks
    private var lastValidTranscription = ""

    enum SpeechError: Error, LocalizedError {
        case notAuthorized
        case notAvailable
        case audioSessionFailed(Error)
        case recognitionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition is not authorized. Please enable it in System Settings > Privacy & Security > Speech Recognition."
            case .notAvailable:
                return "Speech recognition is not available on this device."
            case .audioSessionFailed(let error):
                return "Audio session error: \(error.localizedDescription)"
            case .recognitionFailed(let error):
                return "Recognition error: \(error.localizedDescription)"
            }
        }
    }

    init() {
        print("[SpeechRecognition] Service initialized")
        print("[SpeechRecognition] Recognizer available: \(speechRecognizer?.isAvailable ?? false)")
        print("[SpeechRecognition] Supports on-device: \(speechRecognizer?.supportsOnDeviceRecognition ?? false)")
        checkAuthorization()
    }

    func checkAuthorization() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
        print("[SpeechRecognition] Authorization status: \(authorizationStatusString)")
    }

    private var authorizationStatusString: String {
        switch authorizationStatus {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    func requestAuthorization() async -> Bool {
        print("[SpeechRecognition] Requesting authorization...")
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authorizationStatus = status
                    print("[SpeechRecognition] Authorization result: \(self.authorizationStatusString)")
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    func startRecording() async throws {
        print("[SpeechRecognition] ========================================")
        print("[SpeechRecognition] startRecording called")

        // Check authorization
        if authorizationStatus != .authorized {
            print("[SpeechRecognition] Not authorized, requesting...")
            let authorized = await requestAuthorization()
            if !authorized {
                print("[SpeechRecognition] ERROR: Authorization denied")
                throw SpeechError.notAuthorized
            }
        }

        guard let recognizer = speechRecognizer else {
            print("[SpeechRecognition] ERROR: No speech recognizer available")
            throw SpeechError.notAvailable
        }

        print("[SpeechRecognition] Recognizer locale: \(recognizer.locale.identifier)")
        print("[SpeechRecognition] Recognizer available: \(recognizer.isAvailable)")
        print("[SpeechRecognition] Supports on-device: \(recognizer.supportsOnDeviceRecognition)")

        guard recognizer.isAvailable else {
            print("[SpeechRecognition] ERROR: Recognizer not available")
            throw SpeechError.notAvailable
        }

        // Cancel any existing task
        if recognitionTask != nil {
            print("[SpeechRecognition] Cancelling existing recognition task")
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        // Create recognition request
        print("[SpeechRecognition] Creating recognition request...")
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("[SpeechRecognition] ERROR: Failed to create recognition request")
            throw SpeechError.notAvailable
        }

        recognitionRequest.shouldReportPartialResults = true

        if #available(macOS 13, *) {
            let useOnDevice = recognizer.supportsOnDeviceRecognition
            recognitionRequest.requiresOnDeviceRecognition = useOnDevice
            print("[SpeechRecognition] On-device recognition: \(useOnDevice)")
        }

        // Start recognition task
        print("[SpeechRecognition] Starting recognition task...")
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                // If we're intentionally stopping, ignore callbacks that would overwrite our transcription
                if self.isIntentionallyStopping {
                    print("[SpeechRecognition] Ignoring callback during intentional stop")
                    return
                }

                if let error = error {
                    let nsError = error as NSError
                    print("[SpeechRecognition] Recognition error: \(error)")
                    print("[SpeechRecognition] Error domain: \(nsError.domain)")
                    print("[SpeechRecognition] Error code: \(nsError.code)")

                    // Don't treat cancellation as an error that should stop us
                    // Code 301 = canceled, Code 1110 = no speech detected
                    if nsError.code == 301 || nsError.code == 1110 {
                        print("[SpeechRecognition] Ignoring expected error (canceled or no speech)")
                        return
                    }
                }

                if let result = result {
                    let newTranscription = result.bestTranscription.formattedString
                    // Only update if we have actual content (don't overwrite with empty)
                    if !newTranscription.isEmpty {
                        self.transcription = newTranscription
                        self.lastValidTranscription = newTranscription
                        print("[SpeechRecognition] Transcription update: \"\(self.transcription)\"")
                    } else {
                        print("[SpeechRecognition] Ignoring empty transcription update")
                    }
                    print("[SpeechRecognition] Is final: \(result.isFinal)")
                }

                // Only auto-stop on real errors, not cancellation
                if let error = error {
                    let nsError = error as NSError
                    if nsError.code != 301 && nsError.code != 1110 {
                        print("[SpeechRecognition] Stopping due to real error")
                        self.stopRecordingInternal()
                    }
                }
            }
        }

        // Configure audio input
        print("[SpeechRecognition] Configuring audio input...")

        // Create a fresh audio engine each time
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("[SpeechRecognition] ERROR: Failed to create audio engine")
            throw SpeechError.notAvailable
        }

        // Try to select the built-in microphone for consistent behavior
        selectBuiltInMicrophone()

        let inputNode = audioEngine.inputNode
        let outputFormat = inputNode.outputFormat(forBus: 0)
        print("[SpeechRecognition] Using format: \(outputFormat.sampleRate) Hz, \(outputFormat.channelCount) ch")

        // Validate the format
        guard outputFormat.sampleRate > 0 else {
            print("[SpeechRecognition] ERROR: Invalid sample rate")
            throw SpeechError.notAvailable
        }

        // Install tap
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: outputFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.calculateAudioLevel(buffer: buffer)
        }

        // Start audio engine
        print("[SpeechRecognition] Preparing audio engine...")
        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("[SpeechRecognition] Audio engine started successfully")
        } catch {
            print("[SpeechRecognition] ERROR: Audio engine failed to start: \(error)")
            throw SpeechError.audioSessionFailed(error)
        }

        transcription = ""
        lastValidTranscription = ""
        isRecording = true
        print("[SpeechRecognition] Recording started successfully")
        print("[SpeechRecognition] ========================================")
    }

    func stopRecording() async -> String {
        print("[SpeechRecognition] stopRecording called")

        // Capture the current transcription before stopping
        let capturedTranscription = transcription.isEmpty ? lastValidTranscription : transcription
        print("[SpeechRecognition] Captured transcription before stop: \"\(capturedTranscription)\"")

        // Set flag to ignore callbacks during shutdown
        isIntentionallyStopping = true

        stopRecordingInternal()

        // Small delay to let any pending callbacks finish
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Reset the flag
        isIntentionallyStopping = false

        // Ensure we return the captured transcription
        let finalTranscription = capturedTranscription
        print("[SpeechRecognition] Final transcription: \"\(finalTranscription)\"")
        return finalTranscription
    }

    private func stopRecordingInternal() {
        print("[SpeechRecognition] Stopping internal...")

        // Stop audio engine first
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        // Release the audio engine so next recording gets fresh hardware state
        audioEngine = nil

        // End audio on the request (tells recognizer we're done sending audio)
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // Cancel the task
        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
        audioLevel = 0
        print("[SpeechRecognition] Stopped")
    }

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    /// Attempts to select the built-in microphone as the default input device
    /// This ensures consistent behavior regardless of connected Bluetooth devices
    private func selectBuiltInMicrophone() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            print("[SpeechRecognition] Failed to get audio devices size")
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &audioDevices
        )

        guard status == noErr else {
            print("[SpeechRecognition] Failed to get audio devices")
            return
        }

        // Find the built-in microphone
        for deviceID in audioDevices {
            // Check if device has input
            var inputPropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputPropertyAddress, 0, nil, &inputSize)
            guard status == noErr, inputSize > 0 else { continue }

            // Get device name
            var namePropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var deviceName: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            status = AudioObjectGetPropertyData(deviceID, &namePropertyAddress, 0, nil, &nameSize, &deviceName)

            if status == noErr {
                let name = deviceName as String
                print("[SpeechRecognition] Found input device: \(name) (ID: \(deviceID))")

                // Look for built-in microphone
                if name.lowercased().contains("macbook") || name.lowercased().contains("built-in") {
                    print("[SpeechRecognition] Selecting built-in microphone: \(name)")

                    // Set as default input device
                    var defaultInputAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioHardwarePropertyDefaultInputDevice,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )

                    var mutableDeviceID = deviceID
                    status = AudioObjectSetPropertyData(
                        AudioObjectID(kAudioObjectSystemObject),
                        &defaultInputAddress,
                        0,
                        nil,
                        UInt32(MemoryLayout<AudioDeviceID>.size),
                        &mutableDeviceID
                    )

                    if status == noErr {
                        print("[SpeechRecognition] Successfully set built-in microphone as default")
                    } else {
                        print("[SpeechRecognition] Failed to set default input: \(status)")
                    }
                    return
                }
            }
        }

        print("[SpeechRecognition] Built-in microphone not found, using system default")
    }

    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        // Calculate RMS (Root Mean Square) for audio level
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))

        // Convert to a normalized level (0-1) with some smoothing
        // RMS typically ranges from 0 to ~0.5 for normal speech
        let normalizedLevel = min(rms * 3, 1.0)

        Task { @MainActor in
            // Smooth the transition for more natural animation
            self.audioLevel = self.audioLevel * 0.3 + normalizedLevel * 0.7
        }
    }
}
