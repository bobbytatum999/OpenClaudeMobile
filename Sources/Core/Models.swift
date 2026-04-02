import Foundation

// MARK: - Chat

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case system, user, assistant, tool
    }

    var id = UUID()
    let role: Role
    var content: String
    var updatedAt = Date()
    var isError: Bool = false

    init(id: UUID = UUID(), role: Role, content: String, updatedAt: Date = Date(), isError: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.updatedAt = updatedAt
        self.isError = isError
    }
}

struct ChatSession: Identifiable, Codable {
    var id = UUID()
    var title: String = "New Chat"
    var messages: [ChatMessage] = []
    var createdAt = Date()
    var updatedAt = Date()
    var pinnedAt: Date? = nil

    var isPinned: Bool { pinnedAt != nil }
}

// MARK: - Settings

struct AppSettings: Codable {
    var huggingFaceToken: String = ""
    var selectedRuntime: RuntimeSelection = .remote
    var selectedLocalModelID: String?
    var selectedDocumentIDs: Set<UUID> = []
    var remote = RemoteProviderConfiguration()
    var server = ServerConfiguration()
    var hapticFeedback: Bool = true
    var streamingSpeed: Bool = true

    static let `default` = AppSettings()
}

enum RuntimeSelection: String, Codable, CaseIterable, Identifiable {
    case local, remote
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
    var systemPrompt: String = "You are OpenClaude, a helpful AI assistant running on device. Be concise, accurate, and helpful."
    var temperature: Double = 0.7
    var maxTokens: Int = 4096
}

struct ServerConfiguration: Codable {
    var host: String = "127.0.0.1"
    var port: UInt16 = 8080
    var autoStart: Bool = false
}

// MARK: - HuggingFace

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

    var ggufSiblings: [HuggingFaceSibling] {
        siblings.filter { $0.rfilename.lowercased().hasSuffix(".gguf") }
    }
}

struct HuggingFaceSibling: Codable {
    let rfilename: String
    let size: Int64?

    var filename: String {
        rfilename.components(separatedBy: "/").last ?? rfilename
    }

    /// Detect quantization level from filename e.g. Q4_K_M, Q5_0, f16, IQ2_M
    var quantLabel: String? {
        let name = filename.uppercased()
        let patterns = ["IQ1", "IQ2", "IQ3", "IQ4",
                        "Q2_K", "Q3_K_S", "Q3_K_M", "Q3_K_L",
                        "Q4_0", "Q4_1", "Q4_K_S", "Q4_K_M",
                        "Q5_0", "Q5_1", "Q5_K_S", "Q5_K_M",
                        "Q6_K", "Q8_0", "F16", "BF16", "F32"]
        return patterns.first { name.contains($0) }
    }

    /// Human-readable quality label
    var qualityTier: QuantTier {
        guard let q = quantLabel else { return .unknown }
        if q.hasPrefix("IQ1") || q.hasPrefix("Q2") || q.hasPrefix("IQ2") { return .fast }
        if q.hasPrefix("Q3") || q.hasPrefix("Q4_0") || q.hasPrefix("IQ3") { return .balanced }
        if q.hasPrefix("Q4_K") || q.hasPrefix("Q5") { return .quality }
        if q.hasPrefix("Q6") || q.hasPrefix("Q8") || q.hasPrefix("F") || q.hasPrefix("B") { return .max }
        return .balanced
    }

    var formattedSize: String {
        guard let size else { return "Unknown" }
        let gb = Double(size) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(size) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

enum QuantTier: String {
    case fast = "Fast"
    case balanced = "Balanced"
    case quality = "Quality"
    case max = "Max"
    case unknown = "Unknown"

    var color: String {
        switch self {
        case .fast: return "orange"
        case .balanced: return "yellow"
        case .quality: return "green"
        case .max: return "blue"
        case .unknown: return "gray"
        }
    }

    var systemImage: String {
        switch self {
        case .fast: return "bolt.fill"
        case .balanced: return "gauge.medium"
        case .quality: return "star.fill"
        case .max: return "crown.fill"
        case .unknown: return "questionmark"
        }
    }
}

// MARK: - Installed Model

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

    var quantLabel: String? {
        HuggingFaceSibling(rfilename: filename, size: sizeBytes).quantLabel
    }

    var qualityTier: QuantTier {
        HuggingFaceSibling(rfilename: filename, size: sizeBytes).qualityTier
    }

    var formattedSize: String {
        let gb = Double(sizeBytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(sizeBytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Documents

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

// MARK: - Generation Stats

struct GenerationStats {
    var tokensGenerated: Int = 0
    var startTime: Date = .now
    var endTime: Date? = nil

    var tokensPerSecond: Double {
        let elapsed = (endTime ?? .now).timeIntervalSince(startTime)
        guard elapsed > 0 else { return 0 }
        return Double(tokensGenerated) / elapsed
    }

    var isComplete: Bool { endTime != nil }
}
