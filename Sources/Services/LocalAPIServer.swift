import Foundation
import Network

actor LocalAPIServer {
    enum ServerError: LocalizedError {
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "The local API server is already running."
            }
        }
    }

    struct ChatRequest: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            let role: String
            let content: String
        }
        let model: String?
        let messages: [Message]
        let stream: Bool?
        let temperature: Double?
        let max_tokens: Int?
    }

    private var listener: NWListener?
    private(set) var isRunning = false
    private weak var appModel: AppModel?

    func attach(appModel: AppModel) {
        self.appModel = appModel
    }

    func start(configuration: ServerConfiguration) async throws {
        guard !isRunning else { throw ServerError.alreadyRunning }
        let port = NWEndpoint.Port(rawValue: configuration.port) ?? 8080
        let listener = try NWListener(using: .tcp, on: port)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global(qos: .utility))
            self?.receive(on: connection, buffer: Data())
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task {
                switch state {
                case .ready:
                    await self?.setRunning(true)
                case .failed, .cancelled:
                    await self?.setRunning(false)
                default:
                    break
                }
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func setRunning(_ value: Bool) {
        isRunning = value
    }

    nonisolated private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            if error != nil {
                connection.cancel()
                return
            }
            var accumulator = buffer
            if let data {
                accumulator.append(data)
            }
            if let request = HTTPRequest.parse(from: accumulator) {
                Task { [weak self] in
                    await self?.handle(request: request, on: connection)
                }
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self?.receive(on: connection, buffer: accumulator)
        }
    }

    private func handle(request: HTTPRequest, on connection: NWConnection) async {
        do {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                let payload: [String: Any] = ["status": "ok", "server": "openclaude-mobile", "running": true]
                let body = try JSONSerialization.data(withJSONObject: payload)
                try await sendJSON(body, status: "200 OK", on: connection)
            case ("GET", "/v1/models"):
                let models = await appModel?.apiModelInventory() ?? []
                let payload: [String: Any] = ["object": "list", "data": models]
                let body = try JSONSerialization.data(withJSONObject: payload)
                try await sendJSON(body, status: "200 OK", on: connection)
            case ("POST", "/v1/chat/completions"):
                let decoded = try JSONDecoder().decode(ChatRequest.self, from: request.body)
                if decoded.stream == true {
                    try await sendSSEPrelude(on: connection)
                    let chunks = await appModel?.streamFromAPI(messages: decoded.messages, model: decoded.model, temperature: decoded.temperature, maxTokens: decoded.max_tokens) ?? AsyncThrowingStream<String, Error> { continuation in
                        continuation.finish()
                    }
                    for try await chunk in chunks {
                        let payload: [String: Any] = [
                            "id": UUID().uuidString,
                            "object": "chat.completion.chunk",
                            "choices": [[
                                "index": 0,
                                "delta": ["content": chunk],
                                "finish_reason": NSNull()
                            ]]
                        ]
                        let data = try JSONSerialization.data(withJSONObject: payload)
                        try await sendRaw(Data("data: ".utf8) + data + Data("\n\n".utf8), on: connection)
                    }
                    try await sendRaw(Data("data: [DONE]\n\n".utf8), on: connection)
                    connection.cancel()
                } else {
                    let text = try await appModel?.completeFromAPI(messages: decoded.messages, model: decoded.model, temperature: decoded.temperature, maxTokens: decoded.max_tokens) ?? ""
                    let response = OpenAICompatibleChatResponse(
                        id: UUID().uuidString,
                        object: "chat.completion",
                        created: Int(Date().timeIntervalSince1970),
                        model: decoded.model ?? (await appModel?.currentModelIdentifier() ?? "unknown"),
                        choices: [
                            OpenAICompatibleChatChoice(
                                index: 0,
                                message: .init(role: "assistant", content: text),
                                finishReason: "stop"
                            )
                        ]
                    )
                    let body = try JSONEncoder().encode(response)
                    try await sendJSON(body, status: "200 OK", on: connection)
                }
            default:
                let body = try JSONSerialization.data(withJSONObject: ["error": "Not Found"])
                try await sendJSON(body, status: "404 Not Found", on: connection)
            }
        } catch {
            let body = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data("{\"error\":\"server error\"}".utf8)
            try? await sendJSON(body, status: "500 Internal Server Error", on: connection)
        }
    }

    private func sendJSON(_ body: Data, status: String, on connection: NWConnection) async throws {
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        try await sendRaw(Data(headers.utf8) + body, on: connection)
        connection.cancel()
    }

    private func sendSSEPrelude(on connection: NWConnection) async throws {
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nX-Accel-Buffering: no\r\n\r\n"
        try await sendRaw(Data(headers.utf8), on: connection)
    }

    private func sendRaw(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }
}

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(from data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else { return nil }
        let headerData = data[..<range.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = range.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data[bodyStart..<(bodyStart + contentLength)]
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(body))
    }
}
