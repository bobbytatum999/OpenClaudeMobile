import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var selectedSessionID: UUID?
    @Published var settings: AppSettings = .default
    @Published var installedModels: [InstalledModel] = []
    @Published var searchedModels: [HuggingFaceModelSummary] = []
    @Published var importedDocuments: [ImportedDocument] = []
    @Published var composingText = ""
    @Published var isSending = false
    @Published var isSearchingModels = false
    @Published var isDownloadingModel = false
    @Published var isServerRunning = false
    @Published var statusLine = "Ready"
    @Published var selectedModelDetails: HuggingFaceModelSummary?
    @Published var searchQuery = "qwen2.5-coder"
    @Published var serverBaseURL = "http://127.0.0.1:8080"

    let huggingFace = HuggingFaceService()
    let documents = DocumentService()
    let remote = RemoteProviderService()
    let local = LocalModelEngine()
    let server = LocalAPIServer()

    private let sessionsSaveDebouncer = SaveDebouncer()

    var selectedSessionIndex: Int? {
        guard let selectedSessionID else { return nil }
        return sessions.firstIndex { $0.id == selectedSessionID }
    }

    var selectedSession: ChatSession? {
        guard let index = selectedSessionIndex else { return nil }
        return sessions[index]
    }

    func bootstrap() async {
        sessions = AppPersistence.load([ChatSession].self, from: AppPersistence.sessionsURL, default: [ChatSession()])
        selectedSessionID = sessions.first?.id
        settings = AppPersistence.load(AppSettings.self, from: AppPersistence.settingsURL, default: .default)
        importedDocuments = AppPersistence.load([ImportedDocument].self, from: AppPersistence.documentsURL, default: [])
        installedModels = scanInstalledModels()
        serverBaseURL = "http://\(settings.server.host):\(settings.server.port)"
        await server.attach(appModel: self)
        if settings.server.autoStart {
            do {
                try await startServer()
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func newSession() {
        let session = ChatSession()
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        persistSessions()
    }

    func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        if sessions.isEmpty {
            sessions = [ChatSession()]
        }
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
        }
        persistSessions()
    }

    func saveSettings() {
        do {
            try AppPersistence.save(settings, to: AppPersistence.settingsURL)
            serverBaseURL = "http://\(settings.server.host):\(settings.server.port)"
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func persistDocuments() {
        do {
            try AppPersistence.save(importedDocuments, to: AppPersistence.documentsURL)
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func persistSessions() {
        let sessions = self.sessions
        sessionsSaveDebouncer.schedule {
            try? AppPersistence.save(sessions, to: AppPersistence.sessionsURL)
        }
    }

    func importDocuments(from urls: [URL]) {
        do {
            let imported = try urls.map { try documents.importDocument(from: $0) }
            importedDocuments.insert(contentsOf: imported, at: 0)
            persistDocuments()
            statusLine = "Imported \(imported.count) file(s)"
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func toggleDocumentSelection(_ document: ImportedDocument) {
        if settings.selectedDocumentIDs.contains(document.id) {
            settings.selectedDocumentIDs.remove(document.id)
        } else {
            settings.selectedDocumentIDs.insert(document.id)
        }
        saveSettings()
    }

    func searchHuggingFace() async {
        isSearchingModels = true
        defer { isSearchingModels = false }
        do {
            searchedModels = try await huggingFace.searchModels(query: searchQuery, token: settings.huggingFaceToken)
            selectedModelDetails = searchedModels.first
            statusLine = "Found \(searchedModels.count) model(s)"
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func install(_ model: HuggingFaceModelSummary, sibling: HuggingFaceSibling) async {
        isDownloadingModel = true
        defer { isDownloadingModel = false }
        do {
            let installed = try await huggingFace.downloadGGUF(repoID: model.id, sibling: sibling, token: settings.huggingFaceToken)
            installedModels.removeAll { $0.id == installed.id }
            installedModels.insert(installed, at: 0)
            if settings.selectedLocalModelID == nil {
                settings.selectedLocalModelID = installed.id
                settings.selectedRuntime = .local
                saveSettings()
            }
            statusLine = "Installed \(installed.filename)"
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func sendMessage() async {
        guard let index = selectedSessionIndex else { return }
        let trimmed = composingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSending = true
        let userMessage = ChatMessage(role: .user, content: trimmed)
        sessions[index].messages.append(userMessage)
        sessions[index].updatedAt = .now
        composingText = ""
        let assistantID = UUID()
        sessions[index].messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        persistSessions()

        do {
            let stream = try currentResponseStream(from: sessions[index].messages.dropLast().map { $0 })
            for try await token in stream {
                if let sessionIndex = self.selectedSessionIndex,
                   let messageIndex = self.sessions[sessionIndex].messages.firstIndex(where: { $0.id == assistantID }) {
                    self.sessions[sessionIndex].messages[messageIndex].content += token
                }
            }
            if let titleSource = sessions[index].messages.first(where: { $0.role == .user })?.content, sessions[index].title == "New Chat" {
                sessions[index].title = String(titleSource.prefix(42))
            }
            sessions[index].updatedAt = .now
            statusLine = "Response complete"
            persistSessions()
        } catch {
            if let sessionIndex = selectedSessionIndex,
               let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == assistantID }) {
                sessions[sessionIndex].messages[messageIndex].content = "Error: \(error.localizedDescription)"
            }
            statusLine = error.localizedDescription
            persistSessions()
        }
        isSending = false
    }

    private func currentResponseStream(
        from messages: [ChatMessage],
        runtime: RuntimeSelection? = nil,
        localModelID: String? = nil,
        remoteConfiguration: RemoteProviderConfiguration? = nil
    ) throws -> AsyncThrowingStream<String, Error> {
        let selectedDocs = importedDocuments.filter { settings.selectedDocumentIDs.contains($0.id) }
        let activeRuntime = runtime ?? settings.selectedRuntime
        let activeRemote = remoteConfiguration ?? settings.remote
        if activeRuntime == .local {
            let prompt = PromptBuilder.buildPrompt(messages: messages, selectedDocuments: selectedDocs, systemPrompt: activeRemote.systemPrompt)
            let model = installedModels.first { $0.id == (localModelID ?? settings.selectedLocalModelID) }
            guard let model else {
                throw LocalModelEngine.EngineError.noModelSelected
            }
            return local.generate(prompt: prompt, modelURL: model.fileURL, maxTokens: activeRemote.maxTokens)
        }
        let effectiveMessages = messages + selectedDocs.map {
            ChatMessage(role: .user, content: "[Attached document: \($0.filename)]\n\($0.textPreview)")
        }
        return remote.stream(messages: effectiveMessages, configuration: activeRemote)
    }

    var selectedLocalModel: InstalledModel? {
        guard let id = settings.selectedLocalModelID else { return nil }
        return installedModels.first { $0.id == id }
    }

    func startServer() async throws {
        try await server.start(configuration: settings.server)
        isServerRunning = true
        statusLine = "Server listening on \(serverBaseURL)"
    }

    func stopServer() {
        server.stop()
        isServerRunning = false
        statusLine = "Server stopped"
    }

    func apiModelInventory() -> [[String: String]] {
        var models = installedModels.map {
            ["id": $0.id, "object": "model", "owned_by": "local", "display_name": $0.filename]
        }
        models.append([
            "id": settings.remote.model,
            "object": "model",
            "owned_by": "remote",
            "display_name": settings.remote.model
        ])
        return models
    }

    func currentModelIdentifier() -> String {
        if settings.selectedRuntime == .local, let local = selectedLocalModel {
            return local.id
        }
        return settings.remote.model
    }

    func streamFromAPI(messages: [LocalAPIServer.ChatRequest.Message], model: String?, temperature: Double?, maxTokens: Int?) -> AsyncThrowingStream<String, Error> {
        let mapped = messages.map { ChatMessage(role: ChatMessage.Role(rawValue: $0.role) ?? .user, content: $0.content) }
        var config = settings.remote
        if let model { config.model = model }
        if let temperature { config.temperature = temperature }
        if let maxTokens { config.maxTokens = maxTokens }
        return (try? currentResponseStream(from: mapped, runtime: settings.selectedRuntime, localModelID: settings.selectedLocalModelID, remoteConfiguration: config)) ?? AsyncThrowingStream { continuation in
            continuation.finish(throwing: LocalModelEngine.EngineError.noModelSelected)
        }
    }

    func completeFromAPI(messages: [LocalAPIServer.ChatRequest.Message], model: String?, temperature: Double?, maxTokens: Int?) async throws -> String {
        var text = ""
        let stream = streamFromAPI(messages: messages, model: model, temperature: temperature, maxTokens: maxTokens)
        for try await chunk in stream {
            text += chunk
        }
        return text
    }

    private func scanInstalledModels() -> [InstalledModel] {
        let base = AppPersistence.modelsDirectory
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        var results: [InstalledModel] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "gguf" else { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            let repoDir = url.deletingLastPathComponent().lastPathComponent.replacingOccurrences(of: "__", with: "/")
            results.append(InstalledModel(
                id: "\(repoDir)::\(url.lastPathComponent)",
                repoID: repoDir,
                filename: url.lastPathComponent,
                localPath: url.path,
                sizeBytes: Int64(values?.fileSize ?? 0),
                installedAt: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
            ))
        }
        return results.sorted { $0.installedAt > $1.installedAt }
    }
}

final class SaveDebouncer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "OpenClaudeMobile.SaveDebouncer")
    private var workItem: DispatchWorkItem?

    func schedule(after delay: TimeInterval = 0.35, action: @escaping @Sendable () -> Void) {
        queue.sync {
            workItem?.cancel()
            let item = DispatchWorkItem(block: action)
            workItem = item
            queue.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }
}
