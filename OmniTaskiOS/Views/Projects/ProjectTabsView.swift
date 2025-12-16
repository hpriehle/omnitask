import SwiftUI
import OmniTaskCore

/// Horizontal scrollable project tabs for filtering tasks
struct ProjectTabsView: View {
    let projects: [Project]
    @Binding var selectedProjectId: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

/// Individual project tab button
struct ProjectTab: View {
    let title: String
    let color: Color?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color = color {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }

                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isSelected ? (color ?? Color.primary).opacity(0.12) : Color.clear)
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? (color ?? Color.primary).opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ProjectTabsView(
            projects: [
                Project(name: "Personal", color: "#10B981"),
                Project(name: "Work", color: "#3B82F6"),
                Project(name: "Unsorted", color: "#6B7280")
            ],
            selectedProjectId: .constant(nil)
        )

        ProjectTabsView(
            projects: [
                Project(id: "1", name: "Personal", color: "#10B981"),
                Project(name: "Work", color: "#3B82F6")
            ],
            selectedProjectId: .constant("1")
        )

        ProjectTabsView(
            projects: [
                Project(name: "Personal", color: "#10B981"),
                Project(name: "Work", color: "#3B82F6")
            ],
            selectedProjectId: .constant("all")
        )
    }
    .padding()
}
