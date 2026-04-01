import Foundation

struct RemoteProviderService {
    enum ServiceError: LocalizedError {
        case invalidResponse
        case missingChoice

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The remote provider returned an invalid response."
            case .missingChoice:
                return "The remote provider returned no completion choices."
            }
        }
    }

    struct RequestPayload: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        let stream: Bool
        let temperature: Double
        let max_tokens: Int
    }

    struct ResponsePayload: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let role: String
                let content: String?
            }
            let index: Int
            let message: Message?
            let finish_reason: String?
            let delta: Delta?

            struct Delta: Decodable {
                let content: String?
            }
        }
        let id: String?
        let choices: [Choice]
        let model: String?
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func complete(messages: [ChatMessage], configuration: RemoteProviderConfiguration) async throws -> String {
        let url = endpoint(baseURL: configuration.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 * 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let payload = RequestPayload(
            model: configuration.model,
            messages: makeMessages(messages: messages, systemPrompt: configuration.systemPrompt),
            stream: false,
            temperature: configuration.temperature,
            max_tokens: configuration.maxTokens
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ServiceError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(ResponsePayload.self, from: data)
        guard let content = decoded.choices.first?.message?.content else {
            throw ServiceError.missingChoice
        }
        return content
    }

    func stream(messages: [ChatMessage], configuration: RemoteProviderConfiguration) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = endpoint(baseURL: configuration.baseURL)
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60 * 10
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !configuration.apiKey.isEmpty {
                        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    let payload = RequestPayload(
                        model: configuration.model,
                        messages: makeMessages(messages: messages, systemPrompt: configuration.systemPrompt),
                        stream: true,
                        temperature: configuration.temperature,
                        max_tokens: configuration.maxTokens
                    )
                    request.httpBody = try JSONEncoder().encode(payload)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        throw ServiceError.invalidResponse
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if payload == "[DONE]" {
                            break
                        }
                        guard let data = payload.data(using: .utf8) else { continue }
                        let chunk = try JSONDecoder().decode(ResponsePayload.self, from: data)
                        if let text = chunk.choices.first?.delta?.content, !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func endpoint(baseURL: String) -> URL {
        let normalized = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if normalized.hasSuffix("/chat/completions") {
            return URL(string: normalized)!
        }
        return URL(string: normalized + "/chat/completions")!
    }

    private func makeMessages(messages: [ChatMessage], systemPrompt: String) -> [RequestPayload.Message] {
        var payload: [RequestPayload.Message] = []
        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            payload.append(.init(role: "system", content: prompt))
        }
        payload.append(contentsOf: messages.map { .init(role: $0.role.rawValue, content: $0.content) })
        return payload
    }
}
