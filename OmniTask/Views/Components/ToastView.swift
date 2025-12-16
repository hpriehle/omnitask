import SwiftUI
import OmniTaskCore

/// Compact toast for collapsed pill state - appears above the pill
/// Width is 3x the collapsed pill width (100px) = 300px
struct CompactToastView: View {
    let toast: ToastItem
    let onTap: () -> Void
    let onDismiss: () -> Void

    /// Toast width: 3x the collapsed pill width (100px)
    private let toastWidth: CGFloat = 300

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)

            Text(toast.task.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: toastWidth)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.green.opacity(0.3), lineWidth: 0.5)
        }
        .contentShape(Capsule())
        .onTapGesture {
            onTap()
        }
    }
}

/// Container for compact toasts above the collapsed pill
struct CompactToastContainerView: View {
    @ObservedObject var viewModel: ToastViewModel
    let onExpandAndNavigate: (OmniTask) -> Void

    var body: some View {
        let _ = print("[CompactToastContainerView] Rendering - viewModel object: \(ObjectIdentifier(viewModel)), visibleToasts: \(viewModel.visibleToasts.count)")
        VStack(spacing: 6) {
            ForEach(viewModel.visibleToasts) { toast in
                CompactToastView(
                    toast: toast,
                    onTap: {
                        onExpandAndNavigate(toast.task)
                        viewModel.dismiss(toastId: toast.id)
                    },
                    onDismiss: {
                        viewModel.dismiss(toastId: toast.id)
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }

            if viewModel.queuedCount > 0 {
                Text("+\(viewModel.queuedCount) more")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 300) // Match CompactToastView width
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.visibleToasts)
    }
}

/// Single toast notification view for a created task
struct ToastView: View {
    let toast: ToastItem
    let projects: [OmniTaskCore.Project]
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    private var project: Project? {
        guard let projectId = toast.task.projectId else { return nil }
        return projects.first { $0.id == projectId }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Success indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)

            // Task info
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let project = project {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(project.swiftUIColor)
                            .frame(width: 6, height: 6)
                        Text(project.name)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.green.opacity(0.3), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Container for stacked toast notifications
struct ToastContainerView: View {
    @ObservedObject var viewModel: ToastViewModel
    let projects: [OmniTaskCore.Project]
    let onNavigateToTask: (OmniTask) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.visibleToasts) { toast in
                ToastView(
                    toast: toast,
                    projects: projects,
                    onTap: {
                        onNavigateToTask(toast.task)
                        viewModel.dismiss(toastId: toast.id)
                    },
                    onDismiss: {
                        viewModel.dismiss(toastId: toast.id)
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }

            // Queue indicator
            if viewModel.queuedCount > 0 {
                Text("+\(viewModel.queuedCount) more")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.visibleToasts)
    }
}

// MARK: - Preview

#Preview {
    let viewModel = ToastViewModel()

    return VStack {
        ToastContainerView(
            viewModel: viewModel,
            projects: [],
            onNavigateToTask: { _ in }
        )
        .padding(.top, 90)
        .padding(.horizontal, 12)

        Spacer()

        Button("Add Toast") {
            let task = OmniTask(
                id: UUID().uuidString,
                title: "Test task \(Int.random(in: 1...100))",
                notes: nil,
                projectId: nil,
                parentTaskId: nil,
                priority: .medium,
                dueDate: nil,
                isCompleted: false,
                completedAt: nil,
                sortOrder: 0,
                todaySortOrder: nil,
                isCurrentTask: false,
                recurringPattern: nil,
                originalInput: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            viewModel.addToasts(for: [task])
        }
        .padding()
    }
    .frame(width: 360, height: 500)
    .background(.ultraThinMaterial)
}
