import Foundation

enum RuntimeSelection: String, Codable, CaseIterable, Identifiable {
    case local
    case remote

    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: return "Local"
        case .remote: return "Remote"
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable, CaseIterable {
        case system
        case user
        case assistant
        case tool
    }

    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct ChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "New Chat", messages: [ChatMessage] = [], createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct InstalledModel: Identifiable, Codable, Hashable {
    let id: String
    let repoID: String
    let filename: String
    let localPath: String
    let sizeBytes: Int64
    let installedAt: Date

    var fileURL: URL { URL(fileURLWithPath: localPath) }
    var displayName: String { filename }
}

struct HuggingFaceModelSummary: Identifiable, Codable, Hashable {
    let id: String
    let downloads: Int?
    let likes: Int?
    let pipelineTag: String?
    let privateRepo: Bool
    let lastModified: Date?
    let siblings: [HuggingFaceSibling]

    var ggufFiles: [HuggingFaceSibling] {
        siblings.filter { $0.rfilename.lowercased().hasSuffix(".gguf") }
    }
}

struct HuggingFaceSibling: Identifiable, Codable, Hashable {
    let rfilename: String
    let size: Int64?

    var id: String { rfilename }
    var filename: String { URL(fileURLWithPath: rfilename).lastPathComponent }
}

struct ImportedDocument: Identifiable, Codable, Hashable {
    let id: UUID
    let filename: String
    let localPath: String
    let contentType: String
    let textPreview: String
    let importedAt: Date

    init(id: UUID = UUID(), filename: String, localPath: String, contentType: String, textPreview: String, importedAt: Date = .now) {
        self.id = id
        self.filename = filename
        self.localPath = localPath
        self.contentType = contentType
        self.textPreview = textPreview
        self.importedAt = importedAt
    }

    var fileURL: URL { URL(fileURLWithPath: localPath) }
}

struct RemoteProviderConfiguration: Codable, Equatable {
    var baseURL: String
    var apiKey: String
    var model: String
    var systemPrompt: String
    var temperature: Double
    var maxTokens: Int

    static let `default` = RemoteProviderConfiguration(
        baseURL: "https://api.openai.com/v1",
        apiKey: "",
        model: "gpt-4.1-mini",
        systemPrompt: "You are OpenClaude Mobile, a native iPhone coding and research assistant.",
        temperature: 0.7,
        maxTokens: 1200
    )
}

struct ServerConfiguration: Codable, Equatable {
    var host: String
    var port: UInt16
    var autoStart: Bool

    static let `default` = ServerConfiguration(host: "127.0.0.1", port: 8080, autoStart: false)
}

struct AppSettings: Codable, Equatable {
    var selectedRuntime: RuntimeSelection
    var selectedLocalModelID: String?
    var selectedDocumentIDs: Set<UUID>
    var remote: RemoteProviderConfiguration
    var server: ServerConfiguration
    var huggingFaceToken: String

    static let `default` = AppSettings(
        selectedRuntime: .remote,
        selectedLocalModelID: nil,
        selectedDocumentIDs: [],
        remote: .default,
        server: .default,
        huggingFaceToken: ""
    )
}

struct OpenAICompatibleMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct OpenAICompatibleChatChoice: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }
    let index: Int
    let message: Message
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

struct OpenAICompatibleChatResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAICompatibleChatChoice]
}
