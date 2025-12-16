import SwiftUI
import OmniTaskCore

/// Onboarding overlay - shown over the expanded pill view until completed
struct OnboardingView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var projectVM: ProjectViewModel
    @ObservedObject var taskInputVM: TaskInputViewModel

    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 0) {
            switch currentStep {
            case 0:
                welcomeStep
            case 1:
                apiKeyStep
            case 2:
                projectsStep
            case 3:
                shortcutStep
            case 4:
                firstTaskStep
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Welcome to OmniTask")
                .font(.system(size: 14))

            Button("Get Started") {
                withAnimation {
                    currentStep = 1
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Step 2: API Key

    private var apiKeyStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Add your API Key")
                .font(.system(size: 14))

            VStack(spacing: 12) {
                SecureField("Claude API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Text("Get your API key from [console.anthropic.com](https://console.anthropic.com)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Next") {
                // Save API key to environment
                environment.claudeAPIKey = apiKey
                withAnimation {
                    currentStep = 2
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKey.isEmpty)

            Spacer()
        }
        .padding()
        .onAppear {
            // Pre-fill if already set
            apiKey = environment.claudeAPIKey
        }
    }

    // MARK: - Step 3: Projects

    private var projectsStep: some View {
        VStack(spacing: 16) {
            Text("Configure your projects")
                .font(.system(size: 14))
                .padding(.top, 24)

            OnboardingProjectsView(projectVM: projectVM)
                .frame(maxHeight: .infinity)

            Button("Next") {
                withAnimation {
                    currentStep = 3
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 24)
        }
        .padding(.horizontal)
        .task {
            // Create default projects for onboarding if none exist
            await projectVM.createDefaultProjectsForOnboarding()
        }
    }

    // MARK: - Step 4: Toggle Shortcut

    private var shortcutStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Toggle the Task Window")
                .font(.system(size: 14))

            VStack(spacing: 12) {
                ShortcutRecorderButton(shortcutName: .toggleOmniTask)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)

                Text("Use this shortcut to show/hide OmniTask from anywhere")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Next") {
                withAnimation {
                    currentStep = 4
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Step 5: First Task

    private var firstTaskStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Create your first task")
                .font(.system(size: 14))

            // Reuse TaskInputView
            OnboardingTaskInput(
                taskInputVM: taskInputVM,
                projects: projectVM.projects,
                onTaskCreated: {
                    // Mark onboarding complete
                    environment.hasCompletedOnboarding = true
                    onComplete()
                }
            )
            .frame(maxWidth: 300)

            Text("Hold down the Option key and speak what task you want to add")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Onboarding Projects View

/// Simplified projects view for onboarding
struct OnboardingProjectsView: View {
    @ObservedObject var projectVM: ProjectViewModel
    @State private var editingProject: OmniTaskCore.Project?
    @State private var showingAddProject = false
    @State private var draggingProject: OmniTaskCore.Project?

    var body: some View {
        VStack(spacing: 0) {
            // Project list with drag and drop
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(projectVM.projects) { project in
                        let isLocked = project.name == "Unsorted"

                        projectRow(for: project, isLocked: isLocked)

                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }

            Divider()

            // Add project button
            Button {
                showingAddProject = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add Project")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            // Instruction text
            Text("Drag to reorder. Tap to edit.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .sheet(item: $editingProject) { project in
            ProjectEditorView(projectVM: projectVM, editingProject: project)
        }
        .sheet(isPresented: $showingAddProject) {
            ProjectEditorView(projectVM: projectVM)
        }
    }

    @ViewBuilder
    private func projectRow(for project: OmniTaskCore.Project, isLocked: Bool) -> some View {
        if isLocked {
            // Locked project (Unsorted) - no drag/drop, no tap to edit
            OnboardingProjectRow(project: project, isLocked: true)
                .contentShape(Rectangle())
        } else {
            // Editable project - supports drag/drop and tap to edit
            OnboardingProjectRow(project: project, isLocked: false)
                .background(draggingProject?.id == project.id ? Color.accentColor.opacity(0.1) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    editingProject = project
                }
                .draggable(project.id) {
                    OnboardingProjectRow(project: project, isLocked: false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let droppedId = items.first,
                          let sourceIndex = projectVM.projects.firstIndex(where: { $0.id == droppedId }),
                          let destIndex = projectVM.projects.firstIndex(where: { $0.id == project.id }) else {
                        return false
                    }
                    Task {
                        await projectVM.reorderProjects(
                            from: IndexSet(integer: sourceIndex),
                            to: destIndex > sourceIndex ? destIndex + 1 : destIndex
                        )
                    }
                    return true
                }
        }
    }
}

/// Simplified project row for onboarding
struct OnboardingProjectRow: View {
    let project: OmniTaskCore.Project
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: project.color ?? "#6B7280"))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body)

                if let description = project.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(isLocked ? 0.6 : 1.0)
    }
}

// MARK: - Onboarding Task Input

/// Task input for onboarding - wraps TaskInputView with onboarding-specific behavior
struct OnboardingTaskInput: View {
    @ObservedObject var taskInputVM: TaskInputViewModel
    let projects: [OmniTaskCore.Project]
    let onTaskCreated: () -> Void

    var body: some View {
        TaskInputView(
            viewModel: taskInputVM,
            projects: projects,
            selectedProjectId: nil,
            onTaskCreated: onTaskCreated
        )
        .onAppear {
            // Enable isOnboarding mode for default today due date
            taskInputVM.isOnboarding = true
            // Start monitoring for push-to-talk
            taskInputVM.startMonitoring()
        }
        .onDisappear {
            taskInputVM.isOnboarding = false
            taskInputVM.stopMonitoring()
        }
        // Observe showSuccess to trigger onTaskCreated for voice/text input
        .onChange(of: taskInputVM.showSuccess) { newValue in
            if newValue {
                onTaskCreated()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(
        projectVM: ProjectViewModel(
            projectRepository: ProjectRepository(database: DatabaseManager())
        ),
        taskInputVM: TaskInputViewModel(
            taskStructuringService: TaskStructuringService(
                claudeService: ClaudeService(apiKey: ""),
                projectRepository: ProjectRepository(database: DatabaseManager())
            ),
            taskRepository: TaskRepository(database: DatabaseManager()),
            speechService: SpeechRecognitionService(),
            pushToTalkMonitor: PushToTalkMonitor()
        ),
        onComplete: {}
    )
    .environmentObject(AppEnvironment())
    .frame(width: 360, height: 500)
}
