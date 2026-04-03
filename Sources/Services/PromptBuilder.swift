import Foundation

enum PromptBuilder {
    enum TemplateFamily {
        case llama
        case qwen
        case mistral
        case deepSeek
        case generic
    }

    static func resolveTemplate(modelHint: String?) -> TemplateFamily {
        let hint = modelHint?.lowercased() ?? ""
        if hint.contains("qwen") { return .qwen }
        if hint.contains("mistral") || hint.contains("mixtral") { return .mistral }
        if hint.contains("deepseek") { return .deepSeek }
        if hint.contains("llama") || hint.contains("meta") { return .llama }
        return .generic
    }

    static func buildPrompt(
        messages: [ChatMessage],
        systemPrompt: String,
        documentChunks: [DocumentChunk],
        tools: [ToolDefinition],
        modelHint: String?
    ) -> String {
        let family = resolveTemplate(modelHint: modelHint)
        let documentSection = renderDocumentContext(documentChunks)
        let toolSection = renderToolContext(tools)

        var effectiveSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !documentSection.isEmpty { effectiveSystem += "\n\n" + documentSection }
        if !toolSection.isEmpty { effectiveSystem += "\n\n" + toolSection }

        switch family {
        case .qwen, .generic:
            return chatML(messages: messages, systemPrompt: effectiveSystem)
        case .llama:
            return llama3(messages: messages, systemPrompt: effectiveSystem)
        case .mistral:
            return mistralInstruct(messages: messages, systemPrompt: effectiveSystem)
        case .deepSeek:
            return deepSeek(messages: messages, systemPrompt: effectiveSystem)
        }
    }

    private static func renderDocumentContext(_ chunks: [DocumentChunk]) -> String {
        guard !chunks.isEmpty else { return "" }
        let lines = chunks.prefix(6).map { chunk in
            "[CITE:\(chunk.filename)#\(chunk.id.uuidString.prefix(8))]\n\(chunk.text)"
        }
        return "Relevant document context:\n" + lines.joined(separator: "\n\n")
    }

    private static func renderToolContext(_ tools: [ToolDefinition]) -> String {
        guard !tools.isEmpty else { return "" }
        let toolLines = tools.map { tool in
            "- \(tool.name)(\(tool.parameters.joined(separator: ", "))): \(tool.description)"
        }
        return """
        Available tools:
        \(toolLines.joined(separator: "\n"))

        If a tool is needed, respond with strict JSON only:
        {"tool_call":{"name":"<tool>","arguments":{"key":"value"}}}
        """
    }

    private static func chatML(messages: [ChatMessage], systemPrompt: String) -> String {
        var parts: [String] = []
        if !systemPrompt.isEmpty {
            parts.append("<|im_start|>system\n\(systemPrompt)<|im_end|>")
        }
        for message in messages {
            parts.append("<|im_start|>\(message.role.rawValue)\n\(message.content)<|im_end|>")
        }
        parts.append("<|im_start|>assistant")
        return parts.joined(separator: "\n")
    }

    private static func llama3(messages: [ChatMessage], systemPrompt: String) -> String {
        var parts: [String] = ["<|begin_of_text|>"]
        if !systemPrompt.isEmpty {
            parts.append("<|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>")
        }
        for message in messages {
            parts.append("<|start_header_id|>\(message.role.rawValue)<|end_header_id|>\n\n\(message.content)<|eot_id|>")
        }
        parts.append("<|start_header_id|>assistant<|end_header_id|>\n\n")
        return parts.joined(separator: "")
    }

    private static func mistralInstruct(messages: [ChatMessage], systemPrompt: String) -> String {
        var out = ""
        if !systemPrompt.isEmpty {
            out += "<s>[INST] \(systemPrompt) [/INST]"
        }
        for message in messages {
            switch message.role {
            case .user, .tool:
                out += " [INST] \(message.content) [/INST]"
            case .assistant:
                out += " \(message.content)</s>"
            case .system:
                continue
            }
        }
        return out + " "
    }

    private static func deepSeek(messages: [ChatMessage], systemPrompt: String) -> String {
        var parts: [String] = []
        if !systemPrompt.isEmpty { parts.append("<｜begin▁of▁sentence｜><｜System｜>\(systemPrompt)") }
        for message in messages {
            let role = message.role == .assistant ? "Assistant" : (message.role == .tool ? "Tool" : "User")
            parts.append("<｜\(role)｜>\(message.content)")
        }
        parts.append("<｜Assistant｜>")
        return parts.joined(separator: "\n")
    }
}
