import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    // MARK: - UI State

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
    @Published var downloadProgress: Double?
    @Published var downloadingFilename: String?
    @Published var isServerRunning = false
    @Published var statusLine = "Ready"
    @Published var selectedModelDetails: HuggingFaceModelSummary?
    @Published var searchQuery = "qwen2.5-coder"
    @Published var serverBaseURL = "http://127.0.0.1:8080"
    @Published var generationStats: GenerationStats?
    @Published var showingExportSheet = false
    @Published var exportContent: String = ""
    @Published var toolTraceRows: [ToolTraceRow] = []

    // MARK: - Services

    let huggingFace = HuggingFaceService()
    let documents = DocumentService()
    let documentContext = DocumentContextService()
    let remote = RemoteProviderService()
    let local = LocalModelEngine()
    let server = LocalAPIServer()
    private let settingsStore = SettingsStore()
    private let chatStore = ChatStore()

    private let toolRegistry = ToolRegistry()
    private lazy var toolCoordinator = ToolCoordinator(registry: toolRegistry)
    private lazy var conversationEngine = ConversationEngine(modelManager: ModelManager(), toolCoordinator: toolCoordinator)

    private let sessionsSaveDebouncer = SaveDebouncer()
    private var generationTask: Task<Void, Never>?

    // MARK: - Computed

    var selectedSessionIndex: Int? {
        guard let selectedSessionID else { return nil }
        return sessions.firstIndex { $0.id == selectedSessionID }
    }

    var selectedSession: ChatSession? {
        guard let index = selectedSessionIndex else { return nil }
        return sessions[index]
    }

    var estimatedTokenCount: Int {
        guard let session = selectedSession else { return 0 }
        return session.messages.reduce(0) { $0 + ($1.content.count / 4) }
    }

    var contextFill: Double {
        Double(estimatedTokenCount) / Double(max(settings.remote.maxTokens, 1))
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        sessions = await chatStore.loadSessions()
        selectedSessionID = sessions.first?.id
        settings = settingsStore.load()
        importedDocuments = AppPersistence.load([ImportedDocument].self, from: AppPersistence.documentsURL, default: [])
        installedModels = scanInstalledModels()
        serverBaseURL = "http://\(settings.server.host):\(settings.server.port)"

        await installDefaultTools()
        await server.attach(appModel: self)

        if settings.server.autoStart {
            do { try await startServer() } catch { statusLine = error.localizedDescription }
        }
    }

    private func installDefaultTools() async {
        await toolRegistry.register(SearchDocumentsTool(appModel: self))
        await toolRegistry.register(RuntimeInfoTool(appModel: self))
    }

    // MARK: - Sessions

    func newSession() {
        haptic(.light)
        let session = ChatSession()
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        persistSessions()
    }

    func deleteSession(_ session: ChatSession) {
        haptic(.medium)
        sessions.removeAll { $0.id == session.id }
        if sessions.isEmpty { sessions = [ChatSession()] }
        if selectedSessionID == session.id { selectedSessionID = sessions.first?.id }
        persistSessions()
    }

    func pinSession(_ session: ChatSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].pinnedAt = sessions[index].isPinned ? nil : .now
        persistSessions()
    }

    func renameSession(_ session: ChatSession, to title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].title = title
        persistSessions()
    }

    func deleteMessage(_ message: ChatMessage) {
        guard let sessionIndex = selectedSessionIndex else { return }
        sessions[sessionIndex].messages.removeAll { $0.id == message.id }
        persistSessions()
    }

    func retryLastUserMessage() async {
        guard let idx = selectedSessionIndex else { return }
        guard let lastUser = sessions[idx].messages.last(where: { $0.role == .user }) else { return }
        composingText = lastUser.content
        await sendMessage()
    }

    func updateLastUserMessage(_ text: String) {
        guard let idx = selectedSessionIndex,
              let userIndex = sessions[idx].messages.lastIndex(where: { $0.role == .user }) else { return }
        sessions[idx].messages[userIndex].content = text
        persistSessions()
    }

    // MARK: - Settings

    func saveSettings() {
        do {
            try settingsStore.save(settings)
            serverBaseURL = "http://\(settings.server.host):\(settings.server.port)"
        } catch { statusLine = error.localizedDescription }
    }

    func persistDocuments() {
        do { try AppPersistence.save(importedDocuments, to: AppPersistence.documentsURL) }
        catch { statusLine = error.localizedDescription }
    }

    func persistSessions() {
        let snapshot = sessions
        sessionsSaveDebouncer.schedule {
            Task { await self.chatStore.saveSessions(snapshot) }
        }
    }

    // MARK: - Documents

    func importDocuments(from urls: [URL]) {
        do {
            let imported = try urls.map { try documents.importDocument(from: $0) }
            importedDocuments.insert(contentsOf: imported, at: 0)
            persistDocuments()
            statusLine = "Imported \(imported.count) file(s)"
            haptic(.success)
        } catch { statusLine = error.localizedDescription }
    }

    func toggleDocumentSelection(_ document: ImportedDocument) {
        if settings.selectedDocumentIDs.contains(document.id) {
            settings.selectedDocumentIDs.remove(document.id)
        } else {
            settings.selectedDocumentIDs.insert(document.id)
        }
        saveSettings()
    }

    // MARK: - Models

    func searchHuggingFace() async {
        isSearchingModels = true
        defer { isSearchingModels = false }
        do {
            searchedModels = try await huggingFace.searchModels(query: searchQuery, token: settings.huggingFaceToken)
            selectedModelDetails = searchedModels.first
            statusLine = "Found \(searchedModels.count) model(s)"
        } catch { statusLine = error.localizedDescription }
    }

    func install(_ model: HuggingFaceModelSummary, sibling: HuggingFaceSibling) async {
        isDownloadingModel = true
        downloadProgress = 0.0
        downloadingFilename = sibling.filename
        defer { isDownloadingModel = false; downloadProgress = nil; downloadingFilename = nil }
        do {
            let installed = try await huggingFace.downloadGGUF(repoID: model.id, sibling: sibling, token: settings.huggingFaceToken) { [weak self] progress in
                Task { @MainActor in self?.downloadProgress = progress }
            }
            installedModels.removeAll { $0.id == installed.id }
            installedModels.insert(installed, at: 0)
            if settings.selectedLocalModelID == nil {
                settings.selectedLocalModelID = installed.id
                settings.selectedRuntime = .local
                saveSettings()
            }
            statusLine = "Installed \(installed.filename)"
            haptic(.success)
        } catch { statusLine = error.localizedDescription }
    }

    func uninstallModel(_ model: InstalledModel) {
        try? FileManager.default.removeItem(at: model.fileURL)
        installedModels.removeAll { $0.id == model.id }
        if settings.selectedLocalModelID == model.id {
            settings.selectedLocalModelID = installedModels.first?.id
            saveSettings()
        }
        haptic(.medium)
    }

    // MARK: - Generation

    func sendMessage() async {
        guard !isSending else { return }
        guard let sessionID = selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        let trimmed = composingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        haptic(.light)
        isSending = true
        toolTraceRows.removeAll()

        sessions[index].messages.append(ChatMessage(role: .user, content: trimmed))
        sessions[index].updatedAt = .now
        composingText = ""

        let assistantID = UUID()
        sessions[index].messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        persistSessions()

        let messagesSnapshot = Array(sessions[index].messages.dropLast())
        generationStats = GenerationStats()

        generationTask = Task {
            do {
                let stream = try await self.currentResponseStream(from: messagesSnapshot)
                for try await token in stream {
                    if Task.isCancelled { break }
                    if let liveIndex = self.sessions.firstIndex(where: { $0.id == sessionID }),
                       let msgIndex = self.sessions[liveIndex].messages.firstIndex(where: { $0.id == assistantID }) {
                        self.sessions[liveIndex].messages[msgIndex].content += token
                        self.generationStats?.tokensGenerated += 1
                    }
                }

                if let liveIndex = self.sessions.firstIndex(where: { $0.id == sessionID }),
                   self.sessions[liveIndex].title == "New Chat",
                   let title = self.sessions[liveIndex].messages.first(where: { $0.role == .user })?.content {
                    self.sessions[liveIndex].title = String(title.prefix(42))
                }

                self.generationStats?.endTime = .now
                self.statusLine = String(format: "%.1f tok/s", self.generationStats?.tokensPerSecond ?? 0)
                self.persistSessions()
                self.haptic(.success)
            } catch is CancellationError {
                self.statusLine = "Stopped"
            } catch {
                if let liveIndex = self.sessions.firstIndex(where: { $0.id == sessionID }),
                   let msgIndex = self.sessions[liveIndex].messages.firstIndex(where: { $0.id == assistantID }) {
                    self.sessions[liveIndex].messages[msgIndex].content = error.localizedDescription
                    self.sessions[liveIndex].messages[msgIndex].isError = true
                }
                self.statusLine = error.localizedDescription
                self.haptic(.error)
                self.persistSessions()
            }
            self.isSending = false
        }

        await generationTask?.value
    }

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isSending = false
        haptic(.light)
    }

    func regenerateLastResponse() async {
        guard let sessionID = selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if sessions[index].messages.last?.role == .assistant { sessions[index].messages.removeLast() }
        let assistantID = UUID()
        sessions[index].messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        persistSessions()

        let snapshot = Array(sessions[index].messages.dropLast())
        haptic(.light)
        isSending = true

        generationTask = Task {
            do {
                let stream = try await self.currentResponseStream(from: snapshot)
                for try await token in stream {
                    if let liveIndex = self.sessions.firstIndex(where: { $0.id == sessionID }),
                       let msgIndex = self.sessions[liveIndex].messages.firstIndex(where: { $0.id == assistantID }) {
                        self.sessions[liveIndex].messages[msgIndex].content += token
                    }
                }
                self.persistSessions()
            } catch { self.statusLine = error.localizedDescription }
            self.isSending = false
        }

        await generationTask?.value
    }

    // MARK: - Export / Server / API

    func exportCurrentSession() {
        guard let session = selectedSession else { return }
        var lines: [String] = ["# \(session.title)", ""]
        for msg in session.messages {
            let label = msg.role == .user ? "**You**" : "**Assistant**"
            lines.append("\(label)\n\(msg.content)")
            lines.append("")
        }
        exportContent = lines.joined(separator: "\n")
        showingExportSheet = true
    }

    func startServer() async throws {
        try await server.start(configuration: settings.server)
        isServerRunning = true
        statusLine = "Server listening on \(serverBaseURL)"
    }

    func stopServer() async {
        await server.stop()
        isServerRunning = false
        statusLine = "Server stopped"
    }

    nonisolated func apiModelInventory(installedModels: [InstalledModel], settings: AppSettings) -> [[String: String]] {
        switch settings.selectedRuntime {
        case .local:
            return installedModels.map { ["id": $0.id, "object": "model", "created": "\(Int($0.installedAt.timeIntervalSince1970))", "owned_by": "local"] }
        case .remote:
            return [["id": settings.remote.model, "object": "model", "created": "0", "owned_by": "remote"]]
        }
    }

    func streamFromAPI(messages: [LocalAPIServer.ChatRequest.Message], model: String?, temperature: Double?, maxTokens: Int?) -> AsyncThrowingStream<String, Error> {
        var converted = messages.map { ChatMessage(role: ChatMessage.Role(rawValue: $0.role) ?? .user, content: $0.content) }
        if converted.first?.role != .system, !settings.remote.systemPrompt.isEmpty {
            converted.insert(ChatMessage(role: .system, content: settings.remote.systemPrompt), at: 0)
        }
        var cfg = settings.remote
        if let temp = temperature { cfg.temperature = temp }
        if let maxTokens { cfg.maxTokens = maxTokens }
        if let model { cfg.model = model }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let upstream = try await self.currentResponseStream(from: converted, remoteConfiguration: cfg)
                    for try await token in upstream {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func completeFromAPI(messages: [LocalAPIServer.ChatRequest.Message], model: String?, temperature: Double?, maxTokens: Int?) async throws -> String {
        var text = ""
        for try await chunk in streamFromAPI(messages: messages, model: model, temperature: temperature, maxTokens: maxTokens) {
            text += chunk
        }
        return text
    }

    // MARK: - Internal runtime wiring

    private func currentResponseStream(
        from messages: [ChatMessage],
        runtime: RuntimeSelection? = nil,
        localModelID: String? = nil,
        remoteConfiguration: RemoteProviderConfiguration? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let selectedDocs = importedDocuments.filter { settings.selectedDocumentIDs.contains($0.id) }
        let question = messages.last(where: { $0.role == .user })?.content ?? ""
        let chunks = documentContext.topChunks(from: selectedDocs, query: question)

        let activeRuntime = runtime ?? settings.selectedRuntime
        let remoteCfg = remoteConfiguration ?? settings.remote

        let backend: any ChatBackend
        let modelHint: String?

        if activeRuntime == .local {
            guard let model = installedModels.first(where: { $0.id == (localModelID ?? settings.selectedLocalModelID) }) else {
                throw LocalModelEngine.EngineError.noModelSelected
            }
            backend = LocalChatBackend(engine: local, modelURL: model.fileURL)
            modelHint = model.filename
        } else {
            backend = RemoteChatBackend(remote: remote, configuration: remoteCfg)
            modelHint = remoteCfg.model
        }

        return await conversationEngine.streamConversation(
            seedMessages: messages,
            backend: backend,
            systemPrompt: remoteCfg.systemPrompt,
            sampling: settings.localSampling,
            maxTokens: remoteCfg.maxTokens,
            modelIDHint: modelHint,
            documentContext: chunks,
            onToolEvent: { [weak self] event in
                Task { @MainActor in
                    self?.toolTraceRows.append(
                        ToolTraceRow(name: event.toolName, input: event.input, output: event.output, isError: event.isError)
                    )
                }
            }
        )
    }

    // MARK: - Haptics & models

    enum HapticStyle { case light, medium, heavy, success, error }

    func haptic(_ style: HapticStyle) {
        guard settings.hapticFeedback else { return }
        switch style {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    var selectedLocalModel: InstalledModel? {
        guard let id = settings.selectedLocalModelID else { return nil }
        return installedModels.first { $0.id == id }
    }

    private func scanInstalledModels() -> [InstalledModel] {
        let dir = AppPersistence.modelsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return [] }
        return files.filter { $0.pathExtension.lowercased() == "gguf" }.compactMap { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) } ?? 0
            return InstalledModel(
                id: url.lastPathComponent,
                repoID: url.deletingLastPathComponent().lastPathComponent,
                filename: url.lastPathComponent,
                localPath: url.path,
                sizeBytes: size,
                installedAt: (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .now
            )
        }
    }
}

private final class SearchDocumentsTool: ToolExecutable {
    weak var appModel: AppModel?

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var definition: ToolDefinition {
        ToolDefinition(name: "search_documents", description: "Search imported document chunks by keyword relevance.", parameters: ["query"])
    }

    func run(arguments: [String: String]) async throws -> String {
        guard let appModel else { return "App model unavailable." }
        let q = arguments["query"] ?? ""
        let docs = await MainActor.run {
            appModel.importedDocuments.filter { appModel.settings.selectedDocumentIDs.contains($0.id) }
        }
        let hits = appModel.documentContext.topChunks(from: docs, query: q, limit: 3)
        if hits.isEmpty { return "No relevant chunks found." }
        return hits.map { "[\($0.filename)] \($0.text.prefix(220))" }.joined(separator: "\n\n")
    }
}

private final class RuntimeInfoTool: ToolExecutable {
    weak var appModel: AppModel?

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var definition: ToolDefinition {
        ToolDefinition(name: "runtime_info", description: "Returns local runtime mode, selected model and context stats.", parameters: ["detail"])
    }

    func run(arguments: [String: String]) async throws -> String {
        guard let appModel else { return "App model unavailable." }
        return await MainActor.run {
            "runtime=\(appModel.settings.selectedRuntime.title), model=\(appModel.selectedLocalModel?.filename ?? appModel.settings.remote.model), est_tokens=\(appModel.estimatedTokenCount)"
        }
    }
}

final class SaveDebouncer: @unchecked Sendable {
    private var workItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "SaveDebouncer", qos: .utility)
    func schedule(after delay: TimeInterval = 0.8, _ work: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: work)
        workItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
