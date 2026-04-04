import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    // MARK: - State

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
    @Published var appLogs: [AppLogEntry] = []

    // MARK: - Services

    let huggingFace = HuggingFaceService()
    let documents = DocumentService()
    let remote = RemoteProviderService()
    let local = LocalModelEngine()
    let server = LocalAPIServer()
    let documentContext = DocumentContextService()
    let toolCoordinator = ToolCoordinator()
    lazy var conversationEngine = ConversationEngine(
        local: local,
        remote: remote,
        promptBuilder: PromptBuilder.self,
        documents: documentContext,
        tools: toolCoordinator
    )

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
        // ~4 chars per token rough estimate
        return session.messages.reduce(0) { $0 + ($1.content.count / 4) }
    }

    var contextFill: Double {
        Double(estimatedTokenCount) / Double(max(settings.remote.maxTokens, 1))
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        sessions = AppPersistence.load([ChatSession].self, from: AppPersistence.sessionsURL, default: [ChatSession()])
        selectedSessionID = sessions.first?.id
        settings = AppPersistence.load(AppSettings.self, from: AppPersistence.settingsURL, default: .default)
        importedDocuments = AppPersistence.load([ImportedDocument].self, from: AppPersistence.documentsURL, default: [])
        appLogs = AppPersistence.load([AppLogEntry].self, from: AppPersistence.appLogsURL, default: [])
        installedModels = scanInstalledModels()
        migrateLegacySelectedModelIDIfNeeded()
        registerDefaultTools()
        serverBaseURL = "http://\(settings.server.host):\(settings.server.port)"
        addLog(category: "app", message: "Bootstrap complete. Runtime=\(settings.selectedRuntime.rawValue), models=\(installedModels.count)")
        await server.attach(appModel: self)
        if settings.server.autoStart {
            do { try await startServer() } catch { statusLine = error.localizedDescription }
        }
    }

    // MARK: - Sessions

    func newSession() {
        haptic(.light)
        let session = ChatSession()
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        persistSessions()
        addLog(category: "session", message: "Created new session \(session.id.uuidString.prefix(8))")
    }

    func deleteSession(_ session: ChatSession) {
        haptic(.medium)
        sessions.removeAll { $0.id == session.id }
        if sessions.isEmpty { sessions = [ChatSession()] }
        if selectedSessionID == session.id { selectedSessionID = sessions.first?.id }
        persistSessions()
        addLog(category: "session", message: "Deleted session \(session.id.uuidString.prefix(8))")
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

    // MARK: - Settings

    func saveSettings() {
        do {
            try AppPersistence.save(settings, to: AppPersistence.settingsURL)
            serverBaseURL = "http://\(settings.server.host):\(settings.server.port)"
            addLog(category: "settings", message: "Saved settings")
        } catch { statusLine = error.localizedDescription }
    }

    func persistDocuments() {
        do { try AppPersistence.save(importedDocuments, to: AppPersistence.documentsURL) }
        catch { statusLine = error.localizedDescription }
    }

    func persistSessions() {
        let s = sessions
        sessionsSaveDebouncer.schedule { try? AppPersistence.save(s, to: AppPersistence.sessionsURL) }
    }

    // MARK: - Documents

    func importDocuments(from urls: [URL]) {
        do {
            let imported = try urls.map { try documents.importDocument(from: $0) }
            importedDocuments.insert(contentsOf: imported, at: 0)
            persistDocuments()
            statusLine = "Imported \(imported.count) file(s)"
            haptic(.success)
            addLog(category: "documents", message: "Imported \(imported.count) file(s)")
        } catch { statusLine = error.localizedDescription }
    }

    private func registerDefaultTools() {
        toolCoordinator.register(
            ToolDefinition(
                name: "search_docs",
                description: "Search imported document chunks by keyword overlap.",
                argumentSchema: ["query": "string"]
            ) { [weak self] args in
                guard let self else { return "App model unavailable." }
                let query = args["query"] ?? ""
                let selected = self.importedDocuments.filter { self.settings.selectedDocumentIDs.contains($0.id) }
                let hits = self.documentContext.retrieveTopChunks(query: query, documents: selected, topK: 5)
                if hits.isEmpty { return "No matching document chunks." }
                return hits.map { "\($0.citation)\n\($0.text)" }.joined(separator: "\n\n")
            }
        )
        toolCoordinator.register(
            ToolDefinition(
                name: "list_installed_models",
                description: "List local GGUF models currently installed.",
                argumentSchema: [:]
            ) { [weak self] _ in
                guard let self else { return "App model unavailable." }
                if self.installedModels.isEmpty { return "No installed local models." }
                return self.installedModels.map { "\($0.displayName) (\($0.formattedSize))" }.joined(separator: "\n")
            }
        )
    }

    func toggleDocumentSelection(_ document: ImportedDocument) {
        if settings.selectedDocumentIDs.contains(document.id) {
            settings.selectedDocumentIDs.remove(document.id)
        } else {
            settings.selectedDocumentIDs.insert(document.id)
        }
        saveSettings()
    }

    // MARK: - HuggingFace / Models

    func searchHuggingFace() async {
        isSearchingModels = true
        defer { isSearchingModels = false }
        do {
            searchedModels = try await huggingFace.searchModels(query: searchQuery, token: settings.huggingFaceToken)
            selectedModelDetails = searchedModels.first
            statusLine = "Found \(searchedModels.count) model(s)"
            addLog(category: "models", message: "Search '\(searchQuery)' -> \(searchedModels.count) result(s)")
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
            addLog(category: "models", message: "Installed model \(installed.filename)")
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
        addLog(category: "models", message: "Uninstalled model \(model.filename)")
    }

    // MARK: - Send / Stop / Regenerate

    func sendMessage() async {
        guard !isSending else { return }
        guard let sessionID = selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let trimmed = composingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        haptic(.light)
        isSending = true
        let userMessage = ChatMessage(role: .user, content: trimmed)
        sessions[index].messages.append(userMessage)
        sessions[index].updatedAt = .now
        composingText = ""
        let assistantID = UUID()
        sessions[index].messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        persistSessions()

        let messagesSnapshot = Array(sessions[index].messages.dropLast())
        generationStats = GenerationStats()

        generationTask = Task {
            do {
                self.addLog(category: "chat", message: "Generation started (\(self.settings.selectedRuntime.rawValue))")
                let stream = try self.conversationEngine.streamAgentResponse(
                    messages: messagesSnapshot,
                    settings: self.settings,
                    installedModels: self.installedModels,
                    selectedDocuments: self.importedDocuments.filter { self.settings.selectedDocumentIDs.contains($0.id) },
                    localModelID: self.settings.selectedLocalModelID
                )
                try await self.consumeConversationEvents(stream, sessionID: sessionID, assistantID: assistantID)
                if let liveIndex = self.sessions.firstIndex(where: { $0.id == sessionID }) {
                    if let title = self.sessions[liveIndex].messages.first(where: { $0.role == .user })?.content,
                       self.sessions[liveIndex].title == "New Chat" {
                        self.sessions[liveIndex].title = String(title.prefix(42))
                    }
                    self.sessions[liveIndex].updatedAt = .now
                }
                self.generationStats?.endTime = .now
                self.statusLine = String(format: "%.1f tok/s", self.generationStats?.tokensPerSecond ?? 0)
                self.persistSessions()
                self.haptic(.success)
                self.addLog(category: "chat", message: "Generation completed")
            } catch is CancellationError {
                self.statusLine = "Stopped"
                self.addLog(category: "chat", message: "Generation cancelled", level: .warning)
            } catch {
                if let liveIndex = self.sessions.firstIndex(where: { $0.id == sessionID }),
                   let msgIndex = self.sessions[liveIndex].messages.firstIndex(where: { $0.id == assistantID }) {
                    self.sessions[liveIndex].messages[msgIndex].content = error.localizedDescription
                    self.sessions[liveIndex].messages[msgIndex].isError = true
                }
                self.statusLine = error.localizedDescription
                self.haptic(.error)
                self.persistSessions()
                self.addLog(category: "chat", message: "Generation error: \(error.localizedDescription)", level: .error)
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
        addLog(category: "chat", message: "Stop requested", level: .warning)
    }

    func regenerateLastResponse() async {
        guard let sessionID = selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        // Remove last assistant message
        if sessions[index].messages.last?.role == .assistant {
            sessions[index].messages.removeLast()
        }
        // Re-inject empty assistant placeholder and stream
        let assistantID = UUID()
        sessions[index].messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        persistSessions()

        let messagesSnapshot = Array(sessions[index].messages.dropLast())
        haptic(.light)
        isSending = true
        generationStats = GenerationStats()

        generationTask = Task {
            do {
                let stream = try self.conversationEngine.streamAgentResponse(
                    messages: messagesSnapshot,
                    settings: self.settings,
                    installedModels: self.installedModels,
                    selectedDocuments: self.importedDocuments.filter { self.settings.selectedDocumentIDs.contains($0.id) },
                    localModelID: self.settings.selectedLocalModelID
                )
                try await self.consumeConversationEvents(stream, sessionID: sessionID, assistantID: assistantID)
                self.generationStats?.endTime = .now
                self.statusLine = String(format: "%.1f tok/s", self.generationStats?.tokensPerSecond ?? 0)
                self.persistSessions()
                self.haptic(.success)
            } catch { self.statusLine = error.localizedDescription }
            self.isSending = false
        }
        await generationTask?.value
    }

    // MARK: - Export

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

    // MARK: - Server

    func startServer() async throws {
        try await server.start(configuration: settings.server)
        isServerRunning = true
        statusLine = "Server listening on \(serverBaseURL)"
        addLog(category: "server-control", message: "Server started at \(serverBaseURL)")
    }

    func stopServer() async {
        await server.stop()
        isServerRunning = false
        statusLine = "Server stopped"
        addLog(category: "server-control", message: "Server stopped")
    }

    // MARK: - API (used by LocalAPIServer)

    // Returns a Sendable-safe snapshot for use by the server actor
    nonisolated func apiModelInventory(
        installedModels: [InstalledModel],
        settings: AppSettings
    ) -> [[String: String]] {
        switch settings.selectedRuntime {
        case .local:
            return installedModels.map { m in
                ["id": m.id, "object": "model",
                 "created": "\(Int(m.installedAt.timeIntervalSince1970))",
                 "owned_by": "local"]
            }
        case .remote:
            return [["id": settings.remote.model, "object": "model",
                     "created": "0", "owned_by": "remote"]]
        }
    }

    func streamFromAPI(messages: [LocalAPIServer.ChatRequest.Message], model: String?, temperature: Double?, maxTokens: Int?) -> AsyncThrowingStream<String, Error> {
        var chatMessages: [ChatMessage] = []
        if !settings.remote.systemPrompt.isEmpty {
            chatMessages.append(ChatMessage(role: .system, content: settings.remote.systemPrompt))
        }
        chatMessages += messages.map {
            ChatMessage(role: ChatMessage.Role(rawValue: $0.role) ?? .user, content: $0.content)
        }
        var cfg = settings.remote
        if let t = temperature { cfg.temperature = t }
        if let m = maxTokens { cfg.maxTokens = m }
        if let modelID = model { cfg.model = modelID }
        return (try? currentResponseStream(from: chatMessages, remoteConfiguration: cfg)) ?? AsyncThrowingStream { _ in }
    }

    func completeFromAPI(messages: [LocalAPIServer.ChatRequest.Message], model: String?, temperature: Double?, maxTokens: Int?) async throws -> String {
        var result = ""
        for try await token in streamFromAPI(messages: messages, model: model, temperature: temperature, maxTokens: maxTokens) {
            result += token
        }
        return result
    }

    // MARK: - Private

    func clearAppLogs() {
        appLogs.removeAll()
        persistLogs()
        addLog(category: "app", message: "Logs cleared")
    }

    func exportLogsText() -> String {
        appLogs.map { entry in
            "[\(entry.timestamp.formatted(date: .abbreviated, time: .standard))] [\(entry.level.rawValue.uppercased())] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }

    private func addLog(category: String, message: String, level: AppLogLevel = .info) {
        appLogs.insert(AppLogEntry(level: level, category: category, message: message), at: 0)
        if appLogs.count > 2000 {
            appLogs = Array(appLogs.prefix(2000))
        }
        persistLogs()
    }

    private func persistLogs() {
        try? AppPersistence.save(appLogs, to: AppPersistence.appLogsURL)
    }

    private func consumeConversationEvents(
        _ stream: AsyncThrowingStream<ConversationEvent, Error>,
        sessionID: UUID,
        assistantID: UUID
    ) async throws {
        for try await event in stream {
            if Task.isCancelled { break }
            switch event {
            case .token(let token):
                if let liveIndex = self.sessions.firstIndex(where: { $0.id == sessionID }),
                   let msgIndex = self.sessions[liveIndex].messages.firstIndex(where: { $0.id == assistantID }) {
                    self.sessions[liveIndex].messages[msgIndex].content += token
                    self.generationStats?.tokensGenerated += 1
                }
            case .toolStarted(let name):
                if let liveIndex = self.sessions.firstIndex(where: { $0.id == sessionID }) {
                    self.sessions[liveIndex].messages.append(
                        ChatMessage(role: .tool, content: "Running tool: \(name)")
                    )
                }
                self.addLog(category: "tools", message: "Tool started: \(name)")
            case .toolFinished(let name, let output, let isError):
                if let liveIndex = self.sessions.firstIndex(where: { $0.id == sessionID }) {
                    self.sessions[liveIndex].messages.append(
                        ChatMessage(role: .tool, content: "[\(name)] \(output)", isError: isError)
                    )
                }
                self.addLog(
                    category: "tools",
                    message: "Tool finished: \(name)" + (isError ? " (error)" : ""),
                    level: isError ? .error : .info
                )
            }
        }
    }

    private func currentResponseStream(
        from messages: [ChatMessage],
        runtime: RuntimeSelection? = nil,
        localModelID: String? = nil,
        remoteConfiguration: RemoteProviderConfiguration? = nil
    ) throws -> AsyncThrowingStream<String, Error> {
        let selectedDocs = importedDocuments.filter { settings.selectedDocumentIDs.contains($0.id) }
        let retrieved = documentContext.retrieveTopChunks(
            query: messages.last(where: { $0.role == .user })?.content ?? "",
            documents: selectedDocs,
            topK: settings.retrieval.topK
        )
        let activeRuntime = runtime ?? settings.selectedRuntime
        let activeRemote = remoteConfiguration ?? settings.remote
        if activeRuntime == .local {
            let selectedID = localModelID ?? settings.selectedLocalModelID
            let model = installedModels.first { modelIDMatches($0, selectedID: selectedID) } ?? installedModels.first
            guard let model else { throw LocalModelEngine.EngineError.noModelSelected }
            let prompt = PromptBuilder.buildPrompt(
                template: PromptBuilder.template(forModelHint: model.filename),
                messages: messages,
                retrievedChunks: retrieved,
                systemPrompt: activeRemote.systemPrompt,
                toolDefinitions: []
            )
            return local.generate(prompt: prompt, modelURL: model.fileURL, maxTokens: activeRemote.maxTokens, sampling: settings.localSampling)
        }
        let effectiveMessages = messages + retrieved.map {
            ChatMessage(role: .user, content: "Context \($0.citation):\n\($0.text)")
        }
        return remote.stream(messages: effectiveMessages, configuration: activeRemote)
    }

    // MARK: - Haptics

    enum HapticStyle { case light, medium, heavy, success, error }

    func haptic(_ style: HapticStyle) {
        guard settings.hapticFeedback else { return }
        switch style {
        case .light:   UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:  UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:   UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:   UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - Model Scanning

    var selectedLocalModel: InstalledModel? {
        guard let id = settings.selectedLocalModelID else { return nil }
        return installedModels.first { modelIDMatches($0, selectedID: id) }
    }

    private func modelIDMatches(_ model: InstalledModel, selectedID: String?) -> Bool {
        guard let selectedID else { return false }
        return selectedID == model.id || selectedID == model.filename
    }

    private func migrateLegacySelectedModelIDIfNeeded() {
        guard let selected = settings.selectedLocalModelID else { return }
        guard installedModels.first(where: { $0.id == selected }) == nil else { return }
        guard let migrated = installedModels.first(where: { $0.filename == selected }) else { return }
        settings.selectedLocalModelID = migrated.id
        saveSettings()
    }

    private func scanInstalledModels() -> [InstalledModel] {
        let dir = AppPersistence.modelsDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .compactMap { url in
                let relativeDir = url.deletingLastPathComponent().path.replacingOccurrences(of: dir.path + "/", with: "")
                let repoFolder = relativeDir.isEmpty ? "local" : relativeDir.components(separatedBy: "/").first ?? "local"
                let repoID = repoFolder.replacingOccurrences(of: "__", with: "/")
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) } ?? 0
                return InstalledModel(
                    id: "\(repoID)::\(url.lastPathComponent)",
                    repoID: repoID,
                    filename: url.lastPathComponent,
                    localPath: url.path,
                    sizeBytes: size,
                    installedAt: (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .now
                )
            }
            .sorted { $0.installedAt > $1.installedAt }
    }
}

// MARK: - Debouncer

final class SaveDebouncer: @unchecked Sendable {
    private var workItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "SaveDebouncer", qos: .utility)
    func schedule(after delay: TimeInterval = 0.8, _ work: @escaping () throws -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem { try? work() }
        workItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
