import SwiftUI

/// Horizontal scrollable project tabs
struct ProjectTabsView: View {
    let projects: [Project]
    @Binding var selectedProjectId: String?
    let onAddProject: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // Today tab
                ProjectTab(
                    title: "Today",
                    color: nil,
                    isSelected: selectedProjectId == nil
                ) {
                    selectedProjectId = nil
                }

                // All tab
                ProjectTab(
                    title: "All",
                    color: nil,
                    isSelected: selectedProjectId == "all"
                ) {
                    selectedProjectId = "all"
                }

                // Project tabs
                ForEach(projects) { project in
                    ProjectTab(
                        title: project.name,
                        color: project.swiftUIColor,
                        isSelected: selectedProjectId == project.id
                    ) {
                        selectedProjectId = project.id
                    }
                }

                // Add project button
                Button(action: onAddProject) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

/// Individual project tab
struct ProjectTab: View {
    let title: String
    let color: Color?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color = color {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(isSelected ? (color ?? .primary).opacity(0.15) : Color.clear)
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? (color ?? .primary).opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ProjectTabsView(
            projects: [
                Project(name: "Work", color: "#3B82F6"),
                Project(name: "Personal", color: "#10B981"),
                Project(name: "Unsorted", color: "#6B7280")
            ],
            selectedProjectId: .constant(nil),
            onAddProject: {}
        )

        ProjectTabsView(
            projects: [
                Project(id: "1", name: "Work", color: "#3B82F6"),
                Project(name: "Personal", color: "#10B981")
            ],
            selectedProjectId: .constant("1"),
            onAddProject: {}
        )
    }
    .padding()
    .frame(width: 360)
}
