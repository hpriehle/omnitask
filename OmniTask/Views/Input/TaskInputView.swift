import SwiftUI

/// Input bar for text entry with voice input indicator
struct TaskInputView: View {
    @ObservedObject var viewModel: TaskInputViewModel
    let projects: [Project]
    let onTaskCreated: () -> Void

    @FocusState private var isFocused: Bool
    @State private var showingManualTaskSheet = false

    var body: some View {
        HStack(spacing: 8) {
            // Text field
            TextField(viewModel.placeholder, text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isFocused)
                .disabled(viewModel.isProcessing || viewModel.isRecording)
                .onSubmit {
                    Task { await viewModel.submitText() }
                }

            // Status indicators
            if viewModel.isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
            } else if viewModel.isRecording {
                VoiceInputView(isRecording: viewModel.isRecording)
            } else {
                // Microphone button
                Button {
                    Task { await viewModel.startRecording() }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hold \u{2325} Option to speak")

                // Add task button
                Button {
                    showingManualTaskSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Create task manually")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    viewModel.isRecording ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
        .sheet(isPresented: $showingManualTaskSheet) {
            ManualTaskCreationView(
                projects: projects,
                onCreate: { task in
                    Task {
                        await viewModel.createManualTask(task: task)
                        onTaskCreated()
                    }
                    showingManualTaskSheet = false
                },
                onCancel: {
                    showingManualTaskSheet = false
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusTaskInput)) { _ in
            isFocused = true
        }
    }
}

// MARK: - Preview

#Preview {
    TaskInputView(
        viewModel: TaskInputViewModel(
            taskStructuringService: TaskStructuringService(
                claudeService: ClaudeService(apiKey: ""),
                projectRepository: ProjectRepository(database: DatabaseManager())
            ),
            taskRepository: TaskRepository(database: DatabaseManager()),
            speechService: SpeechRecognitionService(),
            pushToTalkMonitor: PushToTalkMonitor()
        ),
        projects: [
            Project(name: "Work", color: "#3B82F6"),
            Project(name: "Personal", color: "#10B981")
        ],
        onTaskCreated: {}
    )
    .padding()
    .frame(width: 320)
}
