import Foundation

/// Service that uses Claude to structure natural language input into tasks
@MainActor
final class TaskStructuringService {
    private let claudeService: ClaudeService
    private let projectRepository: ProjectRepository

    init(claudeService: ClaudeService, projectRepository: ProjectRepository) {
        self.claudeService = claudeService
        self.projectRepository = projectRepository
    }

    struct ParsedTask: Codable {
        let title: String
        let notes: String?
        let project: String?
        let dueDate: String?
        let priority: String?
        let recurring: Bool?
        let recurrenceRule: String?
        let subtasks: [String]?
        let suggestedOrder: Int?

        enum CodingKeys: String, CodingKey {
            case title, notes, project
            case dueDate = "due_date"
            case priority, recurring
            case recurrenceRule = "recurrence_rule"
            case subtasks
            case suggestedOrder = "suggested_order"
        }
    }

    struct ParseResponse: Codable {
        let tasks: [ParsedTask]
    }

    enum StructuringError: Error, LocalizedError {
        case noAPIKey
        case parsingFailed(String)
        case emptyInput

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key configured. Please add your Claude API key in Settings."
            case .parsingFailed(let reason):
                return "Failed to parse tasks: \(reason)"
            case .emptyInput:
                return "Please enter some text to create a task."
            }
        }
    }

    /// Parse natural language input into structured tasks
    func parseInput(_ input: String) async throws -> [OmniTask] {
        print("[TaskStructuringService] ========================================")
        print("[TaskStructuringService] parseInput called")
        print("[TaskStructuringService] Input: \"\(input)\"")

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("[TaskStructuringService] ERROR: Empty input")
            throw StructuringError.emptyInput
        }

        // Check if API key is available
        let hasKey = await claudeService.hasAPIKey
        print("[TaskStructuringService] Has API key: \(hasKey)")

        guard hasKey else {
            print("[TaskStructuringService] No API key configured - creating simple task (no AI)")
            let task = createSimpleTask(from: trimmed)
            print("[TaskStructuringService] Created simple task: \(task.title)")
            return [task]
        }

        print("[TaskStructuringService] API key found - calling Claude...")

        // Get project context
        let projectContext = try await buildProjectContext()
        print("[TaskStructuringService] Project context: \(projectContext)")

        // Build the prompt
        let systemPrompt = buildSystemPrompt(projectContext: projectContext)
        let userPrompt = buildUserPrompt(input: trimmed)
        print("[TaskStructuringService] User prompt built")

        // Call Claude
        do {
            let response = try await claudeService.sendMessage(
                userMessage: userPrompt,
                systemPrompt: systemPrompt
            )
            print("[TaskStructuringService] Claude response received")
            print("[TaskStructuringService] Response: \(response.prefix(500))...")

            // Parse the response
            let tasks = try parseResponse(response, originalInput: trimmed)
            print("[TaskStructuringService] Parsed \(tasks.count) task(s)")
            for (index, task) in tasks.enumerated() {
                print("[TaskStructuringService] Task \(index + 1): \(task.title)")
            }
            print("[TaskStructuringService] ========================================")
            return tasks
        } catch {
            print("[TaskStructuringService] ERROR: \(error)")
            print("[TaskStructuringService] ========================================")
            throw error
        }
    }

    private func buildProjectContext() async throws -> String {
        let projects = try await projectRepository.projectNamesWithDescriptions()

        if projects.isEmpty {
            return "Available Projects:\n- Unsorted: Default for unclear tasks"
        }

        return "Available Projects:\n" + projects.map { project in
            if let description = project.description, !description.isEmpty {
                return "- \(project.name): \(description)"
            }
            return "- \(project.name)"
        }.joined(separator: "\n")
    }

    private func buildSystemPrompt(projectContext: String) -> String {
        """
        You are a task management assistant. Parse the user's natural language input and structure it into actionable tasks.

        \(projectContext)

        Instructions:
        1. Identify separate tasks vs. subtasks based on dependency and hierarchy
        2. Assign each task to the most appropriate project from the available list (default: "Unsorted")
        3. Parse natural language dates like "tomorrow", "next Monday", "Friday at 3pm", "in 2 hours"
        4. Convert dates to ISO8601 format (e.g., "2025-12-05T14:00:00")
        5. Determine priority: "urgent", "high", "medium", "low", or "none"
        6. Detect recurring patterns like "every Monday", "daily", "weekly"
        7. If input contains multiple distinct tasks, create separate task entries
        8. For compound tasks (task with steps), use subtasks array

        Return ONLY valid JSON in this format, no other text:
        {
          "tasks": [
            {
              "title": "Task title",
              "notes": "Additional context or null",
              "project": "Project name",
              "due_date": "ISO8601 datetime or null",
              "priority": "urgent|high|medium|low|none",
              "recurring": false,
              "recurrence_rule": "null or pattern like 'every Monday'",
              "subtasks": ["Subtask 1", "Subtask 2"],
              "suggested_order": 1
            }
          ]
        }
        """
    }

    private func buildUserPrompt(input: String) -> String {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"

        return """
        Current Date/Time: \(formatter.string(from: now))
        Day of Week: \(dayFormatter.string(from: now))

        Parse this input into tasks:
        "\(input)"
        """
    }

    private func parseResponse(_ response: String, originalInput: String) throws -> [OmniTask] {
        // Extract JSON from the response (in case there's any wrapping text)
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8) else {
            throw StructuringError.parsingFailed("Invalid response format")
        }

        let parseResponse: ParseResponse
        do {
            parseResponse = try JSONDecoder().decode(ParseResponse.self, from: data)
        } catch {
            // If JSON parsing fails, create a simple task with the original input
            return [createSimpleTask(from: originalInput)]
        }

        if parseResponse.tasks.isEmpty {
            return [createSimpleTask(from: originalInput)]
        }

        // Build all tasks including subtasks
        var allTasks: [OmniTask] = []

        for (index, parsed) in parseResponse.tasks.enumerated() {
            let parentTask = try convertToOmniTask(parsed, sortOrder: index, originalInput: originalInput)
            allTasks.append(parentTask)

            // Create subtasks if present
            if let subtaskTitles = parsed.subtasks, !subtaskTitles.isEmpty {
                print("[TaskStructuringService] Creating \(subtaskTitles.count) subtask(s) for: \(parentTask.title)")
                for (subtaskIndex, subtaskTitle) in subtaskTitles.enumerated() {
                    let subtask = OmniTask(
                        title: subtaskTitle,
                        parentTaskId: parentTask.id,
                        priority: parentTask.priority,
                        dueDate: parentTask.dueDate,
                        sortOrder: subtaskIndex
                    )
                    allTasks.append(subtask)
                    print("[TaskStructuringService]   - Subtask: \(subtaskTitle)")
                }
            }
        }

        return allTasks
    }

    private func extractJSON(from response: String) -> String {
        // Find JSON object in the response
        if let startIndex = response.firstIndex(of: "{"),
           let endIndex = response.lastIndex(of: "}") {
            return String(response[startIndex...endIndex])
        }
        return response
    }

    private func convertToOmniTask(_ parsed: ParsedTask, sortOrder: Int, originalInput: String) throws -> OmniTask {
        // Find project ID
        var projectId: String? = nil
        if let projectName = parsed.project {
            if let project = projectRepository.projects.first(where: {
                $0.name.lowercased() == projectName.lowercased()
            }) {
                projectId = project.id
            }
        }

        // Parse due date
        var dueDate: Date? = nil
        if let dueDateString = parsed.dueDate {
            dueDate = parseDate(dueDateString)
        }

        // Parse priority
        let priority = Priority.from(string: parsed.priority ?? "medium")

        // Parse recurring pattern
        var recurringPattern: RecurringPattern? = nil
        if parsed.recurring == true, let rule = parsed.recurrenceRule {
            recurringPattern = RecurringPattern.parse(from: rule)
        }

        // Create the main task
        let task = OmniTask(
            title: parsed.title,
            notes: parsed.notes,
            projectId: projectId,
            priority: priority,
            dueDate: dueDate,
            sortOrder: sortOrder,
            recurringPattern: recurringPattern,
            originalInput: originalInput
        )

        return task
    }

    private func parseDate(_ string: String) -> Date? {
        // Try ISO8601 first
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        // Try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        // Try common formats
        let formatters: [DateFormatter] = {
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd",
            ]
            return formats.map { format in
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.locale = Locale(identifier: "en_US_POSIX")
                return formatter
            }
        }()

        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }

    private func createSimpleTask(from input: String) -> OmniTask {
        OmniTask(
            title: input,
            priority: .medium,
            originalInput: input
        )
    }

    /// Create subtasks for a parent task
    func createSubtasks(for parentId: String, titles: [String]) -> [OmniTask] {
        titles.enumerated().map { index, title in
            OmniTask(
                title: title,
                parentTaskId: parentId,
                priority: .medium,
                sortOrder: index
            )
        }
    }
}
