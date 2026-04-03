import Foundation

struct BackendCapabilities: Sendable {
    var canStream: Bool
    var supportsTools: Bool
    var supportsSystemPrompts: Bool
    var supportsJSONMode: Bool
    var supportsDocuments: Bool

    static let localDefault = BackendCapabilities(
        canStream: true,
        supportsTools: true,
        supportsSystemPrompts: true,
        supportsJSONMode: false,
        supportsDocuments: true
    )

    static let remoteDefault = BackendCapabilities(
        canStream: true,
        supportsTools: false,
        supportsSystemPrompts: true,
        supportsJSONMode: true,
        supportsDocuments: true
    )
}

struct SamplingConfiguration: Codable, Sendable {
    var temperature: Float = 0.7
    var topK: Int = 40
    var topP: Float = 0.92
    var repetitionPenalty: Float = 1.1
    var stopSequences: [String] = ["<|im_end|>", "</s>"]

    static let `default` = SamplingConfiguration()
}

struct GenerationRequest: Sendable {
    var messages: [ChatMessage]
    var modelIDHint: String?
    var systemPrompt: String
    var sampled: SamplingConfiguration
    var maxTokens: Int
    var documentContext: [DocumentChunk]
    var availableTools: [ToolDefinition]
}

struct ToolCall: Codable, Sendable {
    let name: String
    let arguments: [String: String]
}

struct ToolExecutionEvent: Identifiable, Sendable {
    let id = UUID()
    let toolName: String
    let input: [String: String]
    let output: String
    let isError: Bool
}

struct ConversationResult: Sendable {
    var finalText: String
    var trace: [ToolExecutionEvent]
}

struct DocumentChunk: Identifiable, Codable, Sendable {
    let id = UUID()
    let documentID: UUID
    let filename: String
    let text: String
    let score: Double
}
