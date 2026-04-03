import Foundation
import Network

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(from data: Data) -> HTTPRequest? {
        guard let headerBoundary = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }

        let headerData = data.subdata(in: 0..<headerBoundary.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let firstLineParts = requestLine.components(separatedBy: " ")
        guard firstLineParts.count >= 2 else { return nil }
        let method = firstLineParts[0]
        let path = firstLineParts[1]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            // FIX: split on first ": " only so header values containing colons are preserved
            if let colonRange = line.range(of: ": ") {
                let key = String(line[line.startIndex..<colonRange.lowerBound])
                let value = String(line[colonRange.upperBound...])
                headers[key] = value
            }
        }

        let bodyStart = headerBoundary.upperBound
        let declaredBodyLength = headers.first { $0.key.lowercased() == "content-length" }
            .flatMap { Int($0.value.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        let availableBodyLength = data.count - bodyStart
        guard availableBodyLength >= declaredBodyLength else { return nil }

        let bodyEnd = bodyStart + declaredBodyLength
        let body = declaredBodyLength > 0 ? data.subdata(in: bodyStart..<bodyEnd) : Data()
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}

actor LocalAPIServer {
    enum ServerError: LocalizedError {
        case alreadyRunning
        case invalidRequest
        var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "The local API server is already running."
            case .invalidRequest: return "The server received an invalid HTTP request."
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
    // FIX: use a plain stored reference instead of weak — AppModel is @StateObject and lives for app lifetime
    private var appModel: AppModel?

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
            Task { [weak self] in
                await self?.receiveLoop(on: connection)
            }
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

    private func receiveLoop(on connection: NWConnection) async {
        var buffer = Data()
        while true {
            do {
                guard let data = try await receive(on: connection) else {
                    connection.cancel(); break
                }
                buffer.append(data)
                if let request = HTTPRequest.parse(from: buffer) {
                    await handle(request: request, on: connection)
                    buffer.removeAll()
                }
            } catch {
                connection.cancel(); break
            }
        }
    }

    private func receive(on connection: NWConnection) async throws -> Data? {
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if isComplete && data == nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    private func handle(request: HTTPRequest, on connection: NWConnection) async {
        do {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                let payload: [String: Any] = ["status": "ok"]
                let body = try JSONSerialization.data(withJSONObject: payload)
                try await sendJSON(body, status: "200 OK", on: connection)

            case ("GET", "/v1/models"):
                // Capture appModel reference on this actor, then hop to MainActor to read
                // its isolated properties and call the nonisolated inventory helper.
                let localModel = appModel
                let models = await MainActor.run {
                    localModel?.apiModelInventory(
                        installedModels: localModel?.installedModels ?? [],
                        settings: localModel?.settings ?? AppSettings()
                    ) ?? []
                }
                let payload: [String: Any] = ["object": "list", "data": models]
                let body = try JSONSerialization.data(withJSONObject: payload)
                try await sendJSON(body, status: "200 OK", on: connection)

            case ("POST", "/v1/chat/completions"):
                let decoded = try JSONDecoder().decode(ChatRequest.self, from: request.body)
                if decoded.stream == true {
                    try await sendSSEPrelude(on: connection)
                    let stream = await appModel?.streamFromAPI(
                        messages: decoded.messages,
                        model: decoded.model,
                        temperature: decoded.temperature,
                        maxTokens: decoded.max_tokens
                    )
                    if let chunks = stream {
                        for try await chunk in chunks {
                            let payload: [String: Any] = [
                                "id": "chatcmpl-" + UUID().uuidString,
                                "object": "chat.completion.chunk",
                                "created": Int(Date().timeIntervalSince1970),
                                "model": decoded.model ?? "local",
                                "choices": [[
                                    "index": 0,
                                    "delta": ["content": chunk],
                                    "finish_reason": NSNull()
                                ]]
                            ]
                            let data = try JSONSerialization.data(withJSONObject: payload)
                            try await sendRaw(Data("data: ".utf8) + data + Data("\n\n".utf8), on: connection)
                        }
                    }
                    try await sendRaw(Data("data: [DONE]\n\n".utf8), on: connection)
                    connection.cancel()
                } else {
                    let text = try await appModel?.completeFromAPI(
                        messages: decoded.messages,
                        model: decoded.model,
                        temperature: decoded.temperature,
                        maxTokens: decoded.max_tokens
                    ) ?? ""
                    let response = OpenAICompatibleResponse(
                        id: "chatcmpl-" + UUID().uuidString,
                        object: "chat.completion",
                        created: Int(Date().timeIntervalSince1970),
                        model: decoded.model ?? "local",
                        choices: [OpenAICompatibleChoice(
                            index: 0,
                            message: .init(role: "assistant", content: text),
                            finish_reason: "stop"
                        )]
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
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        try await sendRaw(Data(headers.utf8) + body, on: connection)
        connection.cancel()
    }

    private func sendSSEPrelude(on connection: NWConnection) async throws {
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\nX-Accel-Buffering: no\r\n\r\n"
        try await sendRaw(Data(headers.utf8), on: connection)
    }

    private func sendRaw(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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

struct OpenAICompatibleResponse: Encodable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAICompatibleChoice]
}

struct OpenAICompatibleChoice: Encodable {
    let index: Int
    let message: OpenAICompatibleMessage
    let finish_reason: String
}

struct OpenAICompatibleMessage: Encodable {
    let role: String
    let content: String
}
