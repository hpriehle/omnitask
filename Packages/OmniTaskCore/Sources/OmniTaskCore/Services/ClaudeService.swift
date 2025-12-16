import Foundation

/// Service for communicating with the Anthropic Claude API
public actor ClaudeService {
    private var apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-sonnet-4-20250514"

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func updateAPIKey(_ newKey: String) {
        self.apiKey = newKey
    }

    public var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    public struct Message: Codable, Sendable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public struct Request: Codable, Sendable {
        public let model: String
        public let max_tokens: Int
        public let system: String?
        public let messages: [Message]

        public init(model: String, max_tokens: Int, system: String?, messages: [Message]) {
            self.model = model
            self.max_tokens = max_tokens
            self.system = system
            self.messages = messages
        }
    }

    public struct ContentBlock: Codable, Sendable {
        public let type: String
        public let text: String?
    }

    public struct Response: Codable, Sendable {
        public let id: String
        public let content: [ContentBlock]
        public let stop_reason: String?
    }

    public struct ErrorResponse: Codable, Sendable {
        public struct Error: Codable, Sendable {
            public let type: String
            public let message: String
        }
        public let error: Error
    }

    public enum ClaudeError: Error, LocalizedError, Sendable {
        case noAPIKey
        case networkError(String)
        case invalidResponse
        case apiError(String)
        case decodingError(String)

        public var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No Claude API key configured. Please add your API key in Settings."
            case .networkError(let message):
                return "Network error: \(message)"
            case .invalidResponse:
                return "Invalid response from Claude API"
            case .apiError(let message):
                return "Claude API error: \(message)"
            case .decodingError(let message):
                return "Failed to decode response: \(message)"
            }
        }
    }

    public func sendMessage(
        userMessage: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 1000
    ) async throws -> String {
        print("[ClaudeService] sendMessage called")
        print("[ClaudeService] API key present: \(!apiKey.isEmpty)")
        print("[ClaudeService] API key length: \(apiKey.count)")

        guard !apiKey.isEmpty else {
            print("[ClaudeService] ERROR: No API key configured!")
            throw ClaudeError.noAPIKey
        }

        print("[ClaudeService] User message: \(userMessage.prefix(100))...")
        print("[ClaudeService] System prompt: \(systemPrompt?.prefix(50) ?? "none")...")
        print("[ClaudeService] Model: \(model)")

        let requestBody = Request(
            model: model,
            max_tokens: maxTokens,
            system: systemPrompt,
            messages: [Message(role: "user", content: userMessage)]
        )

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            print("[ClaudeService] Request body encoded successfully")
        } catch {
            print("[ClaudeService] ERROR encoding request: \(error)")
            throw ClaudeError.decodingError(error.localizedDescription)
        }

        print("[ClaudeService] Sending request to API...")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
            print("[ClaudeService] Response received, data size: \(data.count) bytes")
        } catch {
            print("[ClaudeService] ERROR network request failed: \(error)")
            throw ClaudeError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[ClaudeService] ERROR: Invalid response type")
            throw ClaudeError.invalidResponse
        }

        print("[ClaudeService] HTTP status code: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode"
            print("[ClaudeService] ERROR response body: \(responseString)")
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                print("[ClaudeService] API error: \(errorResponse.error.message)")
                throw ClaudeError.apiError(errorResponse.error.message)
            }
            throw ClaudeError.apiError("HTTP \(httpResponse.statusCode)")
        }

        do {
            let claudeResponse = try JSONDecoder().decode(Response.self, from: data)
            guard let textContent = claudeResponse.content.first(where: { $0.type == "text" }),
                  let text = textContent.text else {
                print("[ClaudeService] ERROR: No text content in response")
                throw ClaudeError.invalidResponse
            }
            print("[ClaudeService] SUCCESS - Response text length: \(text.count)")
            print("[ClaudeService] Response preview: \(text.prefix(200))...")
            return text
        } catch let error as ClaudeError {
            throw error
        } catch {
            print("[ClaudeService] ERROR decoding response: \(error)")
            throw ClaudeError.decodingError(error.localizedDescription)
        }
    }
}
