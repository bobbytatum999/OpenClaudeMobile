import Foundation

enum ConversationEvent: Sendable {
    case token(String)
    case toolStarted(String)
    case toolFinished(name: String, output: String, isError: Bool)
}

struct ConversationEngine {
    let local: LocalModelEngine
    let remote: RemoteProviderService
    let promptBuilder: PromptBuilder.Type
    let documents: DocumentContextService
    let tools: ToolCoordinator

    func streamAgentResponse(
        messages: [ChatMessage],
        settings: AppSettings,
        installedModels: [InstalledModel],
        selectedDocuments: [ImportedDocument],
        localModelID: String?
    ) throws -> AsyncThrowingStream<ConversationEvent, Error> {
        let maxToolSteps = 3

        return AsyncThrowingStream { continuation in
            let task = Task {
                var workingMessages = messages

                for _ in 0..<maxToolSteps {
                    var assistantText = ""
                    let stream = try makeStream(
                        messages: workingMessages,
                        settings: settings,
                        installedModels: installedModels,
                        selectedDocuments: selectedDocuments,
                        localModelID: localModelID
                    )
                    for try await token in stream {
                        assistantText += token
                        continuation.yield(.token(token))
                    }

                    if let call = tools.parseToolCall(from: assistantText) {
                        continuation.yield(.toolStarted(call.name))
                        let result = await tools.execute(call)
                        continuation.yield(.toolFinished(name: result.name, output: result.output, isError: result.isError))
                        workingMessages.append(ChatMessage(role: .assistant, content: assistantText))
                        workingMessages.append(ChatMessage(role: .tool, content: "[\(result.name)] \(result.output)", isError: result.isError))
                        continue
                    }

                    break
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeStream(
        messages: [ChatMessage],
        settings: AppSettings,
        installedModels: [InstalledModel],
        selectedDocuments: [ImportedDocument],
        localModelID: String?
    ) throws -> AsyncThrowingStream<String, Error> {
        let retrieved = documents.retrieveTopChunks(
            query: messages.last(where: { $0.role == .user })?.content ?? "",
            documents: selectedDocuments,
            topK: settings.retrieval.topK
        )

        let template = PromptBuilder.template(forModelHint: installedModels.first { $0.id == (localModelID ?? settings.selectedLocalModelID) }?.filename)
        let prompt = promptBuilder.buildPrompt(
            template: template,
            messages: messages,
            retrievedChunks: retrieved,
            systemPrompt: settings.remote.systemPrompt,
            toolDefinitions: []
        )

        if settings.selectedRuntime == .local {
            guard let model = installedModels.first(where: { $0.id == (localModelID ?? settings.selectedLocalModelID) }) ?? installedModels.first else {
                throw LocalModelEngine.EngineError.noModelSelected
            }
            return local.generate(
                prompt: prompt,
                modelURL: model.fileURL,
                maxTokens: settings.remote.maxTokens,
                sampling: settings.localSampling
            )
        }
        let remoteMessages = messages + retrieved.map {
            ChatMessage(role: .user, content: "Context \($0.citation):\n\($0.text)")
        }
        return remote.stream(messages: remoteMessages, configuration: settings.remote)
    }
}
