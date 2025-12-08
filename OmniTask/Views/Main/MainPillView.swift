import SwiftUI

/// Root view for the floating pill - switches between collapsed and expanded states
struct MainPillView: View {
    @Binding var isExpanded: Bool
    @EnvironmentObject var environment: AppEnvironment

    @State private var taskListVM: TaskListViewModel?
    @State private var taskInputVM: TaskInputViewModel?
    @State private var projectVM: ProjectViewModel?
    @State private var isInitialized = false

    var body: some View {
        let _ = print("[MainPillView] body evaluated, isExpanded: \(isExpanded), initialized: \(isInitialized)")
        let anchor = environment.expansionState.anchor.unitPoint

        Group {
            if isInitialized,
               let taskListVM = taskListVM,
               let taskInputVM = taskInputVM,
               let projectVM = projectVM {
                ZStack {
                    if isExpanded {
                        ExpandedPillView(
                            isExpanded: $isExpanded,
                            taskListVM: taskListVM,
                            taskInputVM: taskInputVM,
                            projectVM: projectVM
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8, anchor: anchor).combined(with: .opacity),
                            removal: .scale(scale: 0.8, anchor: anchor).combined(with: .opacity)
                        ))
                    } else {
                        CollapsedPillView(
                            isExpanded: $isExpanded,
                            taskCount: taskListVM.todayTaskCount,
                            taskListVM: taskListVM,
                            taskInputVM: taskInputVM,
                            onHide: { duration in
                                NotificationCenter.default.post(
                                    name: .hidePillRequested,
                                    object: nil,
                                    userInfo: duration.map { ["duration": $0] }
                                )
                            },
                            onSizeChange: { newSize in
                                NotificationCenter.default.post(
                                    name: .pillSizeChanged,
                                    object: nil,
                                    userInfo: ["size": newSize]
                                )
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 1.2, anchor: anchor).combined(with: .opacity),
                            removal: .scale(scale: 1.2, anchor: anchor).combined(with: .opacity)
                        ))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
            } else {
                // Loading state while ViewModels initialize
                Color.clear
                    .frame(width: 120, height: 40)
            }
        }
        .onAppear {
            print("[MainPillView] onAppear - initializing view models with environment")
            initializeViewModels()
        }
        .onDisappear {
            print("[MainPillView] onDisappear - stopping monitoring")
            taskInputVM?.stopMonitoring()
        }
    }

    private func initializeViewModels() {
        guard !isInitialized else {
            print("[MainPillView] Already initialized, skipping")
            return
        }

        print("[MainPillView] Creating ViewModels with environment services")
        print("[MainPillView] Environment claudeAPIKey length: \(environment.claudeAPIKey.count)")

        // Use the REAL services from AppEnvironment
        let newTaskListVM = TaskListViewModel(
            taskRepository: environment.taskRepository,
            projectRepository: environment.projectRepository
        )

        let newTaskInputVM = TaskInputViewModel(
            taskStructuringService: environment.taskStructuringService,
            taskRepository: environment.taskRepository,
            speechService: environment.speechRecognitionService,
            pushToTalkMonitor: environment.pushToTalkMonitor
        )

        let newProjectVM = ProjectViewModel(
            projectRepository: environment.projectRepository
        )

        self.taskListVM = newTaskListVM
        self.taskInputVM = newTaskInputVM
        self.projectVM = newProjectVM
        self.isInitialized = true

        newTaskInputVM.startMonitoring()
        print("[MainPillView] ViewModels initialized and monitoring started")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let hidePillRequested = Notification.Name("hidePillRequested")
    static let pillSizeChanged = Notification.Name("pillSizeChanged")
    static let focusTaskInput = Notification.Name("focusTaskInput")
}

// MARK: - Preview

#Preview {
    MainPillView(isExpanded: .constant(true))
        .environmentObject(AppEnvironment())
        .frame(width: 360, height: 500)
}
