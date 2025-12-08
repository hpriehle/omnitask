import Foundation

/// Handles omnitask:// URL scheme
@MainActor
final class URLSchemeHandler {
    enum Action {
        case addTask(text: String, project: String?)
        case openProject(name: String)
        case openToday
        case toggle
        case unknown
    }

    /// Parses a URL and returns the appropriate action
    func parse(url: URL) -> Action {
        guard url.scheme == "omnitask" else {
            return .unknown
        }

        let host = url.host ?? ""
        let path = url.path

        switch host {
        case "add":
            // omnitask://add?task=...&project=...
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return .unknown
            }

            let task = components.queryItems?.first(where: { $0.name == "task" })?.value ?? ""
            let project = components.queryItems?.first(where: { $0.name == "project" })?.value

            if !task.isEmpty {
                return .addTask(text: task, project: project)
            }
            return .unknown

        case "project":
            // omnitask://project/ProjectName
            let projectName = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !projectName.isEmpty {
                return .openProject(name: projectName)
            }
            return .unknown

        case "today":
            // omnitask://today
            return .openToday

        case "toggle":
            // omnitask://toggle
            return .toggle

        default:
            return .unknown
        }
    }

    /// Handle the URL and perform the action
    func handle(url: URL) {
        let action = parse(url: url)

        switch action {
        case .addTask(let text, let project):
            NotificationCenter.default.post(
                name: .addTaskFromURL,
                object: nil,
                userInfo: ["text": text, "project": project as Any]
            )

        case .openProject(let name):
            NotificationCenter.default.post(
                name: .openProjectFromURL,
                object: nil,
                userInfo: ["name": name]
            )

        case .openToday:
            NotificationCenter.default.post(name: .openTodayFromURL, object: nil)

        case .toggle:
            NotificationCenter.default.post(name: .toggleFromURL, object: nil)

        case .unknown:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let addTaskFromURL = Notification.Name("addTaskFromURL")
    static let openProjectFromURL = Notification.Name("openProjectFromURL")
    static let openTodayFromURL = Notification.Name("openTodayFromURL")
    static let toggleFromURL = Notification.Name("toggleFromURL")
}
