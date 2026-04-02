import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
        case tool
    }
    
    var id = UUID()
    let role: Role
    var content: String
    var updatedAt = Date()
    
    init(id: UUID = UUID(), role: Role, content: String, updatedAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.updatedAt = updatedAt
    }
}

struct ChatSession: Identifiable, Codable {
    var id = UUID()
    var title: String = "New Chat"
    var messages: [ChatMessage] = []
    var createdAt = Date()
    var updatedAt = Date()
}

struct AppSettings: Codable {
    var huggingFaceToken: String = ""
    var selectedRuntime: RuntimeSelection = .remote
    var selectedLocalModelID: String?
    var selectedDocumentIDs: Set<UUID> = []
    var remote = RemoteProviderConfiguration()
    var server = ServerConfiguration()
    
    static let `default` = AppSettings()
}

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

struct RemoteProviderConfiguration: Codable {
    var baseURL: String = "https://api.anthropic.com/v1"
    var apiKey: String = ""
    var model: String = "claude-3-5-sonnet-20240620"
    var systemPrompt: String = "You are OpenClaude, a helpful AI assistant."
    var temperature: Double = 0.7
    var maxTokens: Int = 4096
}

struct ServerConfiguration: Codable {
    var host: String = "127.0.0.1"
    var port: UInt16 = 8080
    var autoStart: Bool = false
}

struct HuggingFaceModelSummary: Identifiable, Codable {
    let id: String
    let downloads: Int?
    let likes: Int?
    let pipelineTag: String?
    let privateRepo: Bool
    let lastModified: Date?
    let siblings: [HuggingFaceSibling]
    
    var displayName: String {
        id.components(separatedBy: "/").last ?? id
    }
}

struct HuggingFaceSibling: Codable {
    let rfilename: String
    let size: Int64?
    
    var filename: String {
        rfilename.components(separatedBy: "/").last ?? rfilename
    }
}

struct InstalledModel: Identifiable, Codable {
    let id: String
    let repoID: String
    let filename: String
    let localPath: String
    let sizeBytes: Int64
    let installedAt: Date
    
    var fileURL: URL {
        URL(fileURLWithPath: localPath)
    }
    
    var displayName: String {
        filename.replacingOccurrences(of: ".gguf", with: "", options: .caseInsensitive)
    }
}

struct ImportedDocument: Identifiable, Codable {
    var id = UUID()
    let filename: String
    let localPath: String
    let contentType: String
    let textPreview: String
    
    var fileURL: URL {
        URL(fileURLWithPath: localPath)
    }
}
