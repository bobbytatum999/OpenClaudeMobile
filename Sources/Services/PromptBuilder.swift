import Foundation

enum PromptTemplate {
    case llama
    case qwen
    case mistral
    case deepSeek
    case chatMLFallback
}

enum PromptBuilder {
    static func template(forModelHint hint: String?) -> PromptTemplate {
        let h = (hint ?? "").lowercased()
        if h.contains("qwen") { return .qwen }
        if h.contains("mistral") { return .mistral }
        if h.contains("deepseek") { return .deepSeek }
        if h.contains("llama") || h.contains("meta") { return .llama }
        return .chatMLFallback
    }

    static func buildPrompt(
        template: PromptTemplate,
        messages: [ChatMessage],
        retrievedChunks: [RetrievedChunk],
        systemPrompt: String,
        toolDefinitions: [ToolDefinition]
    ) -> String {
        let toolsSpec = toolDefinitions.isEmpty ? "" : """
        Available tools:
        \(toolDefinitions.map { "- \($0.name): \($0.description). Args: \($0.argumentSchema)" }.joined(separator: "\n"))
        Tool call format:
        <tool_call>{"name":"tool_name","arguments":{"key":"value"}}</tool_call>
        """

        let retrievalSpec = retrievedChunks.isEmpty ? "" : """
        Context snippets:
        \(retrievedChunks.map { "\($0.citation)\n\($0.text)" }.joined(separator: "\n\n"))
        """

        let mergedSystem = [systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines), toolsSpec, retrievalSpec]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        switch template {
        case .llama: return llamaStyle(messages: messages, systemPrompt: mergedSystem)
        case .qwen: return qwenStyle(messages: messages, systemPrompt: mergedSystem)
        case .mistral: return mistralStyle(messages: messages, systemPrompt: mergedSystem)
        case .deepSeek: return deepSeekStyle(messages: messages, systemPrompt: mergedSystem)
        case .chatMLFallback: return chatMLStyle(messages: messages, systemPrompt: mergedSystem)
        }
    }

    private static func chatMLStyle(messages: [ChatMessage], systemPrompt: String) -> String {
        var parts: [String] = []
        if !systemPrompt.isEmpty {
            parts.append("<|im_start|>system\n\(systemPrompt)<|im_end|>")
        }
        for msg in messages {
            parts.append("<|im_start|>\(msg.role.rawValue)\n\(msg.content)<|im_end|>")
        }
        parts.append("<|im_start|>assistant")
        return parts.joined(separator: "\n")
    }

    private static func llamaStyle(messages: [ChatMessage], systemPrompt: String) -> String {
        var parts: [String] = []
        if !systemPrompt.isEmpty {
            parts.append("<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\(systemPrompt)<|eot_id|>")
        } else {
            parts.append("<|begin_of_text|>")
        }
        for msg in messages {
            parts.append("<|start_header_id|>\(msg.role.rawValue)<|end_header_id|>\n\(msg.content)<|eot_id|>")
        }
        parts.append("<|start_header_id|>assistant<|end_header_id|>\n")
        return parts.joined(separator: "\n")
    }

    private static func qwenStyle(messages: [ChatMessage], systemPrompt: String) -> String {
        var parts: [String] = []
        if !systemPrompt.isEmpty {
            parts.append("<|im_start|>system\n\(systemPrompt)<|im_end|>")
        }
        for msg in messages {
            parts.append("<|im_start|>\(msg.role.rawValue)\n\(msg.content)<|im_end|>")
        }
        parts.append("<|im_start|>assistant\n")
        return parts.joined(separator: "\n")
    }

    private static func mistralStyle(messages: [ChatMessage], systemPrompt: String) -> String {
        var parts: [String] = []
        var seeded = false
        for msg in messages {
            switch msg.role {
            case .user:
                let prefix = !seeded && !systemPrompt.isEmpty ? "\(systemPrompt)\n\n" : ""
                parts.append("<s>[INST] \(prefix)\(msg.content) [/INST]")
                seeded = true
            case .assistant:
                parts.append("\(msg.content)</s>")
            case .tool:
                parts.append("[TOOL] \(msg.content)")
            case .system:
                continue
            }
        }
        if parts.isEmpty {
            parts.append("<s>[INST] \(systemPrompt) [/INST]")
        }
        return parts.joined(separator: "\n")
    }

    private static func deepSeekStyle(messages: [ChatMessage], systemPrompt: String) -> String {
        var parts: [String] = []
        if !systemPrompt.isEmpty {
            parts.append("### System:\n\(systemPrompt)")
        }
        for msg in messages {
            parts.append("### \(msg.role.rawValue.capitalized):\n\(msg.content)")
        }
        parts.append("### Assistant:\n")
        return parts.joined(separator: "\n\n")
    }
}
