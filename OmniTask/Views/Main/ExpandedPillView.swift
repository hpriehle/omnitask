import SwiftUI

/// Expanded state of the floating pill - full task interface
struct ExpandedPillView: View {
    @Binding var isExpanded: Bool
    @ObservedObject var taskListVM: TaskListViewModel
    @ObservedObject var taskInputVM: TaskInputViewModel
    @ObservedObject var projectVM: ProjectViewModel
    @EnvironmentObject var environment: AppEnvironment

    @State private var showingSettings = false
    @State private var showingFilterMenu = false
    @State private var showingProjectEditor = false
    @State private var keyboardMonitor: Any?

    var body: some View {
        let _ = print("[ExpandedPillView] body evaluated, showingSettings: \(showingSettings), hasCompletedOnboarding: \(environment.hasCompletedOnboarding)")
        ZStack {
            // Main content layer
            VStack(spacing: 0) {
                if showingSettings {
                    // Settings drawer - replaces main content
                    settingsDrawer
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    // Normal content
                    mainContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }

            // Onboarding overlay - shown when not complete
            if !environment.hasCompletedOnboarding {
                OnboardingView(
                    projectVM: projectVM,
                    taskInputVM: taskInputVM,
                    onComplete: {
                        print("[ExpandedPillView] Onboarding completed")
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(width: 360, height: 500)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingSettings)
        .sheet(isPresented: $showingProjectEditor) {
            ProjectEditorView(projectVM: projectVM)
        }
        .task {
            print("[ExpandedPillView] task - loading tasks")
            await taskListVM.loadTasks()
            print("[ExpandedPillView] task - tasks loaded")
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack(alignment: .top) {
            // Main content
            VStack(spacing: 0) {
                // No API Key banner
                if taskInputVM.showNoAPIKeyError {
                    noAPIKeyBanner
                }

                // Header with input
                headerSection

                Divider()

                // Project tabs
                ProjectTabsView(
                    projects: projectVM.projects,
                    selectedProjectId: $projectVM.selectedProjectId,
                    onAddProject: {
                        print("[ExpandedPillView] Add project tapped")
                        showingProjectEditor = true
                    }
                )
                .onChange(of: projectVM.selectedProjectId) { newValue in
                    print("[ExpandedPillView] Project selection changed to: \(newValue ?? "nil")")
                    taskListVM.selectProject(newValue)
                }

                Divider()

                // Task list
                taskListSection

                // Current task footer (sticky at bottom, always visible)
                if let currentTask = taskListVM.currentTask {
                    Divider()
                    CurrentTaskFooter(
                        task: currentTask,
                        projects: projectVM.projects,
                        onComplete: {
                            await taskListVM.completeCurrentTask()
                        },
                        onEdit: {
                            Task { await taskListVM.loadTasks() }
                        },
                        onUnstar: {
                            Task {
                                await taskListVM.clearCurrentTask()
                                await taskListVM.loadTasks()
                                await taskListVM.loadTodayTasksFlat()
                            }
                        },
                        subtaskCount: taskListVM.subtaskCountFor(currentTask.id),
                        subtasks: taskListVM.subtasksFor(currentTask.id),
                        isExpanded: taskListVM.isExpanded(currentTask.id),
                        onToggleExpand: {
                            Task { await taskListVM.toggleExpanded(currentTask.id) }
                        },
                        onCompleteSubtask: { subtask in
                            Task { await taskListVM.completeSubtask(subtask) }
                        },
                        onUpdateSubtask: { updatedSubtask in
                            Task { await taskListVM.updateTask(updatedSubtask) }
                        },
                        isKeyboardSelected: taskListVM.isCurrentTaskSelected,
                        canComplete: taskListVM.canCompleteParent(currentTask.id)
                    )
                    .id(currentTask.id)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                Divider()

                // Footer menu
                footerSection
            }

            // Filter menu overlay (slides down from header)
            if showingFilterMenu {
                VStack(spacing: 0) {
                    // Spacer to position just below the title bar (filter icon row)
                    Color.clear.frame(height: 44)

                    // Menu content
                    FilterSortMenuView(settings: $environment.filterSettings)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 12)

                    // Tap-to-dismiss area fills remaining space
                    Color.black.opacity(0.001)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingFilterMenu = false
                            }
                        }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            // Select current task in footer on appear
            taskListVM.selectCurrentTaskInFooter()
            setupKeyboardMonitor()
            // Sync filter settings from environment
            taskListVM.filterSettings = environment.filterSettings
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onChange(of: projectVM.selectedProjectId) { _ in
            // Clear selection when changing views
            taskListVM.clearSelection()
        }
        .onChange(of: environment.filterSettings) { newSettings in
            // Sync filter settings and reload tasks
            taskListVM.filterSettings = newSettings
            Task { await taskListVM.loadTasks() }
        }
    }

    // MARK: - Keyboard Handling

    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Don't handle shortcuts when settings drawer is open
            if showingSettings { return event }

            return handleKeyEvent(event) ? nil : event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = modifiers.contains(.command)

        // Arrow keys
        if event.keyCode == 125 { // Down arrow
            taskListVM.selectNextTask()
            return true
        }

        if event.keyCode == 126 { // Up arrow
            taskListVM.selectPreviousTask()
            return true
        }

        // Return/Enter key
        if event.keyCode == 36 && hasCommand { // Cmd+Return
            Task { await taskListVM.completeSelectedTask() }
            return true
        }

        // Character keys
        guard let chars = event.charactersIgnoringModifiers else { return false }

        if hasCommand {
            switch chars {
            case "1":
                projectVM.selectToday()
                return true
            case "2":
                projectVM.selectAll()
                return true
            case "3":
                projectVM.selectProjectByIndex(0)
                return true
            case "4":
                projectVM.selectProjectByIndex(1)
                return true
            case "5":
                projectVM.selectProjectByIndex(2)
                return true
            case "6":
                projectVM.selectProjectByIndex(3)
                return true
            case "7":
                projectVM.selectProjectByIndex(4)
                return true
            case "8":
                projectVM.selectProjectByIndex(5)
                return true
            case "9":
                projectVM.selectProjectByIndex(6)
                return true
            case "t", "T":
                // Cmd+T - add subtask
                taskListVM.addSubtaskToSelected()
                return true
            case "s", "S":
                // Cmd+S - toggle as current/starred task
                Task { await taskListVM.toggleSelectedAsCurrent() }
                return true
            default:
                break
            }
        }

        return false
    }

    // MARK: - Settings Drawer

    private var settingsDrawer: some View {
        let _ = print("[ExpandedPillView] Rendering settings drawer")
        return VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button {
                    print("[ExpandedPillView] Settings back button tapped")
                    showingSettings = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.headline)

                Spacer()

                // Invisible spacer for symmetry
                Color.clear
                    .frame(width: 50, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Settings content
            SettingsView(projectVM: projectVM)
                .environmentObject(environment)
        }
        .onAppear {
            print("[ExpandedPillView] Settings drawer appeared")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            // Title bar with controls
            HStack {
                // Close button (X) - closes to pill
                Button {
                    print("[ExpandedPillView] Close button tapped")
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // AI processing indicator (centered)
                if taskInputVM.isProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("AI working...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                }

                Spacer()

                // Filter button
                Button {
                    print("[ExpandedPillView] Filter button tapped")
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingFilterMenu.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14))
                        .foregroundColor(environment.filterSettings.hasActiveFilters ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                // Settings button (gear icon)
                Button {
                    print("[ExpandedPillView] Settings button tapped")
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .animation(.easeInOut(duration: 0.2), value: taskInputVM.isProcessing)

            // Input bar
            TaskInputView(
                viewModel: taskInputVM,
                projects: projectVM.projects,
                onTaskCreated: {
                    Task { await taskListVM.loadTasks() }
                }
            )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Task List Section

    private var taskListSection: some View {
        Group {
            if taskListVM.selectedProjectId == nil {
                // Today tab - flat list with drag-drop reordering
                todayFlatList
            } else {
                // Other tabs - grouped view
                groupedTaskList
            }
        }
    }

    /// Today tab: flat list with drag-drop reordering
    private var todayFlatList: some View {
        List {
            if taskListVM.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if taskListVM.todayTasksFlat.isEmpty && taskListVM.overdueTasks.isEmpty && taskListVM.currentTask == nil {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(taskListVM.todayTasksFlat) { task in
                    // Skip current task (shown in footer)
                    if !taskListVM.isCurrentTask(task.id) {
                        VStack(spacing: 0) {
                            TaskRowView(
                                task: task,
                                projects: projectVM.projects,
                                tagRepository: environment.tagRepository,
                                subtaskCount: taskListVM.subtaskCountFor(task.id),
                                isExpanded: taskListVM.isExpanded(task.id),
                                canComplete: taskListVM.canCompleteParent(task.id),
                                onComplete: {
                                    print("[ExpandedPillView] Task completed: \(task.title)")
                                    Task { await taskListVM.completeTask(task) }
                                },
                                onUpdate: { updatedTask in
                                    print("[ExpandedPillView] Task updated: \(updatedTask.title)")
                                    Task { await taskListVM.updateTask(updatedTask) }
                                },
                                onToggleExpand: {
                                    Task { await taskListVM.toggleExpanded(task.id) }
                                },
                                onAddSubtask: {
                                    taskListVM.startAddingSubtask(to: task.id)
                                },
                                isInTodayView: true,
                                onQuickDateAction: {
                                    Task { await taskListVM.deferBy24Hours(task) }
                                },
                                isCurrentTask: false,
                                onSetCurrentTask: {
                                    Task { await taskListVM.setCurrentTask(task) }
                                },
                                showProjectDot: true,
                                isKeyboardSelected: taskListVM.selectedTaskId == task.id
                            )

                            // Expanded subtasks
                            if taskListVM.isExpanded(task.id) {
                                ForEach(taskListVM.subtasksFor(task.id)) { subtask in
                                    SubtaskRowView(
                                        task: subtask,
                                        projects: projectVM.projects,
                                        tagRepository: environment.tagRepository,
                                        onComplete: {
                                            Task { await taskListVM.completeSubtask(subtask) }
                                        },
                                        onUpdate: { updatedSubtask in
                                            Task { await taskListVM.updateTask(updatedSubtask) }
                                        },
                                        onDelete: {
                                            Task { await taskListVM.deleteSubtask(subtask) }
                                        },
                                        isKeyboardSelected: taskListVM.selectedTaskId == subtask.id
                                    )
                                }

                                // Inline subtask input
                                if taskListVM.isAddingSubtask(to: task.id) {
                                    InlineSubtaskInput(
                                        parentId: task.id,
                                        onSubmit: { title in
                                            Task { await taskListVM.createSubtask(parentId: task.id, title: title) }
                                        },
                                        onCancel: {
                                            taskListVM.cancelAddingSubtask()
                                        }
                                    )
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .onMove { source, destination in
                    Task { await taskListVM.reorderTodayTasks(from: source, to: destination) }
                }

                // Overdue tasks section
                if !taskListVM.overdueTasks.isEmpty {
                    Section {
                        if !taskListVM.isOverdueSectionCollapsed {
                            ForEach(taskListVM.overdueTasks) { task in
                                // Skip current task (shown in footer)
                                if !taskListVM.isCurrentTask(task.id) {
                                    VStack(spacing: 0) {
                                        TaskRowView(
                                            task: task,
                                            projects: projectVM.projects,
                                            tagRepository: environment.tagRepository,
                                            subtaskCount: taskListVM.subtaskCountFor(task.id),
                                            isExpanded: taskListVM.isExpanded(task.id),
                                            canComplete: taskListVM.canCompleteParent(task.id),
                                            onComplete: {
                                                print("[ExpandedPillView] Overdue task completed: \(task.title)")
                                                Task { await taskListVM.completeTask(task) }
                                            },
                                            onUpdate: { updatedTask in
                                                print("[ExpandedPillView] Overdue task updated: \(updatedTask.title)")
                                                Task { await taskListVM.updateTask(updatedTask) }
                                            },
                                            onToggleExpand: {
                                                Task { await taskListVM.toggleExpanded(task.id) }
                                            },
                                            onAddSubtask: {
                                                taskListVM.startAddingSubtask(to: task.id)
                                            },
                                            isInTodayView: true,
                                            onQuickDateAction: {
                                                Task { await taskListVM.setDueToday(task) }
                                            },
                                            isCurrentTask: false,
                                            onSetCurrentTask: {
                                                Task { await taskListVM.setCurrentTask(task) }
                                            },
                                            showProjectDot: true,
                                            isKeyboardSelected: taskListVM.selectedTaskId == task.id
                                        )

                                        // Expanded subtasks
                                        if taskListVM.isExpanded(task.id) {
                                            ForEach(taskListVM.subtasksFor(task.id)) { subtask in
                                                SubtaskRowView(
                                                    task: subtask,
                                                    projects: projectVM.projects,
                                                    tagRepository: environment.tagRepository,
                                                    onComplete: {
                                                        Task { await taskListVM.completeSubtask(subtask) }
                                                    },
                                                    onUpdate: { updatedSubtask in
                                                        Task { await taskListVM.updateTask(updatedSubtask) }
                                                    },
                                                    onDelete: {
                                                        Task { await taskListVM.deleteSubtask(subtask) }
                                                    },
                                                    isKeyboardSelected: taskListVM.selectedTaskId == subtask.id
                                                )
                                            }

                                            // Inline subtask input
                                            if taskListVM.isAddingSubtask(to: task.id) {
                                                InlineSubtaskInput(
                                                    parentId: task.id,
                                                    onSubmit: { title in
                                                        Task { await taskListVM.createSubtask(parentId: task.id, title: title) }
                                                    },
                                                    onCancel: {
                                                        taskListVM.cancelAddingSubtask()
                                                    }
                                                )
                                            }
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                            }
                        }
                    } header: {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                taskListVM.isOverdueSectionCollapsed.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: taskListVM.isOverdueSectionCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 12)

                                Text("Overdue")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.03))
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }

                // Completed tasks section (at the bottom)
                if !taskListVM.completedTasks.isEmpty {
                    Section {
                        ForEach(taskListVM.completedTasks) { task in
                            CompletedTaskRowView(
                                task: task,
                                projects: projectVM.projects,
                                onUncomplete: {
                                    Task { await taskListVM.uncompleteTask(task) }
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)

                            Text("Completed")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(taskListVM.completedTasks.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.05))
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .task {
            await taskListVM.loadTodayTasksFlat()
        }
    }

    /// Other tabs: grouped by project
    private var groupedTaskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if taskListVM.isLoading {
                    ProgressView()
                        .padding()
                } else if taskListVM.tasks.isEmpty {
                    emptyState
                } else {
                    ForEach(taskListVM.groupedTasks, id: \.project?.id) { group in
                        if projectVM.selectedProjectId == "all" {
                            // Show project header in All view
                            projectHeader(group.project)
                        }

                        ForEach(group.tasks) { task in
                            // Skip current task (shown in footer)
                            if !taskListVM.isCurrentTask(task.id) {
                                // Parent task row
                                TaskRowView(
                                    task: task,
                                    projects: projectVM.projects,
                                    tagRepository: environment.tagRepository,
                                    subtaskCount: taskListVM.subtaskCountFor(task.id),
                                    isExpanded: taskListVM.isExpanded(task.id),
                                    canComplete: taskListVM.canCompleteParent(task.id),
                                    onComplete: {
                                        print("[ExpandedPillView] Task completed: \(task.title)")
                                        Task { await taskListVM.completeTask(task) }
                                    },
                                    onUpdate: { updatedTask in
                                        print("[ExpandedPillView] Task updated: \(updatedTask.title)")
                                        Task { await taskListVM.updateTask(updatedTask) }
                                    },
                                    onToggleExpand: {
                                        Task { await taskListVM.toggleExpanded(task.id) }
                                    },
                                    onAddSubtask: {
                                        taskListVM.startAddingSubtask(to: task.id)
                                    },
                                    isInTodayView: false,
                                    onQuickDateAction: {
                                        Task { await taskListVM.setDueToday(task) }
                                    },
                                    isCurrentTask: taskListVM.isCurrentTask(task.id),
                                    onSetCurrentTask: {
                                        Task { await taskListVM.setCurrentTask(task) }
                                    },
                                    showProjectDot: projectVM.selectedProjectId == "all",
                                    isKeyboardSelected: taskListVM.selectedTaskId == task.id
                                )

                                // Expanded subtasks
                                if taskListVM.isExpanded(task.id) {
                                    ForEach(taskListVM.subtasksFor(task.id)) { subtask in
                                        SubtaskRowView(
                                            task: subtask,
                                            projects: projectVM.projects,
                                            tagRepository: environment.tagRepository,
                                            onComplete: {
                                                Task { await taskListVM.completeSubtask(subtask) }
                                            },
                                            onUpdate: { updatedSubtask in
                                                Task { await taskListVM.updateTask(updatedSubtask) }
                                            },
                                            onDelete: {
                                                Task { await taskListVM.deleteSubtask(subtask) }
                                            },
                                            isKeyboardSelected: taskListVM.selectedTaskId == subtask.id
                                        )
                                    }

                                    // Inline subtask input
                                    if taskListVM.isAddingSubtask(to: task.id) {
                                        InlineSubtaskInput(
                                            parentId: task.id,
                                            onSubmit: { title in
                                                Task { await taskListVM.createSubtask(parentId: task.id, title: title) }
                                            },
                                            onCancel: {
                                                taskListVM.cancelAddingSubtask()
                                            }
                                        )
                                    }
                                }
                            } // end if !isCurrentTask
                        }
                    }

                    // Completed tasks section (at the bottom)
                    if !taskListVM.completedTasks.isEmpty {
                        completedTasksSection
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// Completed tasks section (shown when showCompleted is enabled)
    private var completedTasksSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green)

                Text("Completed")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(taskListVM.completedTasks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.05))

            // Completed tasks
            ForEach(taskListVM.completedTasks) { task in
                CompletedTaskRowView(
                    task: task,
                    projects: projectVM.projects,
                    onUncomplete: {
                        Task { await taskListVM.uncompleteTask(task) }
                    }
                )
            }
        }
    }

    private func projectHeader(_ project: Project?) -> some View {
        HStack {
            Circle()
                .fill(project?.swiftUIColor ?? Color.gray)
                .frame(width: 8, height: 8)

            Text(project?.name ?? "Unsorted")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No tasks")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Type above or hold \u{2325} to add a task")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - No API Key Banner

    private var noAPIKeyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))

            Text("No API Key added.")
                .font(.subheadline)
                .foregroundColor(.primary)

            Button {
                print("[ExpandedPillView] No API Key banner - opening settings")
                taskInputVM.dismissNoAPIKeyError()
                showingSettings = true
            } label: {
                Text("Click here to add")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    .underline()
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                print("[ExpandedPillView] Dismissing no API key banner")
                taskInputVM.dismissNoAPIKeyError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.orange.opacity(0.3)),
            alignment: .bottom
        )
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            if let errorMessage = taskListVM.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

#Preview {
    ExpandedPillView(
        isExpanded: .constant(true),
        taskListVM: TaskListViewModel(
            taskRepository: TaskRepository(database: DatabaseManager()),
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
        projectVM: ProjectViewModel(
            projectRepository: ProjectRepository(database: DatabaseManager())
        )
    )
    .environmentObject(AppEnvironment())
    .frame(width: 360, height: 500)
}
