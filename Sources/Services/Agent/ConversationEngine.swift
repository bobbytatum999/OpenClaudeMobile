import Foundation

actor ConversationEngine {
    struct EngineConfig: Sendable {
        var maxToolSteps: Int = 4
    }

    private let modelManager: ModelManager
    private let toolCoordinator: ToolCoordinator
    private let config: EngineConfig

    init(modelManager: ModelManager, toolCoordinator: ToolCoordinator, config: EngineConfig = .init()) {
        self.modelManager = modelManager
        self.toolCoordinator = toolCoordinator
        self.config = config
    }

    func streamConversation(
        seedMessages: [ChatMessage],
        backend: any ChatBackend,
        systemPrompt: String,
        sampling: SamplingConfiguration,
        maxTokens: Int,
        modelIDHint: String?,
        documentContext: [DocumentChunk],
        onToolEvent: (@Sendable (ToolExecutionEvent) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var working = seedMessages
                    var steps = 0

                    while steps <= config.maxToolSteps {
                        let tools = await toolCoordinator.availableTools()
                        let request = GenerationRequest(
                            messages: working,
                            modelIDHint: modelIDHint,
                            systemPrompt: systemPrompt,
                            sampled: sampling,
                            maxTokens: maxTokens,
                            documentContext: documentContext,
                            availableTools: tools
                        )

                        var assistantText = ""
                        let stream = try await modelManager.stream(with: backend, request: request)
                        for try await token in stream {
                            assistantText += token
                            continuation.yield(token)
                        }

                        guard backend.capabilities.supportsTools,
                              let toolEvent = await toolCoordinator.attemptToolExecution(from: assistantText) else {
                            continuation.finish()
                            return
                        }

                        onToolEvent?(toolEvent)
                        working.append(ChatMessage(role: .assistant, content: assistantText))
                        let toolPayload = "TOOL[\(toolEvent.toolName)] => \(toolEvent.output)"
                        working.append(ChatMessage(role: .tool, content: toolPayload))
                        steps += 1
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
