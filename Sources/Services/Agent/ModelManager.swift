import Foundation

protocol ChatBackend: Sendable {
    var capabilities: BackendCapabilities { get }
    func stream(request: GenerationRequest) throws -> AsyncThrowingStream<String, Error>
}

struct LocalChatBackend: ChatBackend {
    let capabilities: BackendCapabilities = .localDefault
    let engine: LocalModelEngine
    let modelURL: URL

    func stream(request: GenerationRequest) throws -> AsyncThrowingStream<String, Error> {
        let prompt = PromptBuilder.buildPrompt(
            messages: request.messages,
            systemPrompt: request.systemPrompt,
            documentChunks: request.documentContext,
            tools: request.availableTools,
            modelHint: request.modelIDHint
        )
        let localRequest = LocalGenerationRequest(
            prompt: prompt,
            modelURL: modelURL,
            maxTokens: request.maxTokens,
            sampling: request.sampled
        )
        return engine.generate(request: localRequest)
    }
}

struct RemoteChatBackend: ChatBackend {
    let capabilities: BackendCapabilities = .remoteDefault
    let remote: RemoteProviderService
    let configuration: RemoteProviderConfiguration

    func stream(request: GenerationRequest) throws -> AsyncThrowingStream<String, Error> {
        let withDocs = request.messages + request.documentContext.map {
            ChatMessage(role: .system, content: "[doc:\($0.filename)#\($0.id.uuidString.prefix(6))] \($0.text)")
        }
        return remote.stream(messages: withDocs, configuration: configuration)
    }
}

actor ModelManager {
    func stream(with backend: any ChatBackend, request: GenerationRequest) throws -> AsyncThrowingStream<String, Error> {
        try backend.stream(request: request)
    }
}
