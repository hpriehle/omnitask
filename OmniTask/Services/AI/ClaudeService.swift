import Foundation

/// Service for communicating with the Anthropic Claude API
actor ClaudeService {
    private var apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-sonnet-4-20250514"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func updateAPIKey(_ newKey: String) {
        self.apiKey = newKey
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct Request: Codable {
        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [Message]
    }

    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }

    struct Response: Codable {
        let id: String
        let content: [ContentBlock]
        let stop_reason: String?
    }

    struct ErrorResponse: Codable {
        struct Error: Codable {
            let type: String
            let message: String
        }
        let error: Error
    }

    enum ClaudeError: Error, LocalizedError {
        case noAPIKey
        case networkError(Error)
        case invalidResponse
        case apiError(String)
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No Claude API key configured. Please add your API key in Settings."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from Claude API"
            case .apiError(let message):
                return "Claude API error: \(message)"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            }
        }
    }

    func sendMessage(
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
            throw ClaudeError.decodingError(error)
        }

        print("[ClaudeService] Sending request to API...")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
            print("[ClaudeService] Response received, data size: \(data.count) bytes")
        } catch {
            print("[ClaudeService] ERROR network request failed: \(error)")
            throw ClaudeError.networkError(error)
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
            throw ClaudeError.decodingError(error)
        }
    }
}
