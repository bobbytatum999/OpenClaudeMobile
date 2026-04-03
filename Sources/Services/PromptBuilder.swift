import Foundation

enum PromptBuilder {
    /// Builds a ChatML-formatted prompt string for local GGUF models.
    /// Most modern GGUF models (Qwen2, Llama3, Mistral) use ChatML or similar formats.
    /// Format: <|im_start|>role\ncontent<|im_end|>\n
    static func buildPrompt(messages: [ChatMessage], selectedDocuments: [ImportedDocument], systemPrompt: String) -> String {
        var parts: [String] = []

        // System turn
        var systemContent = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedDocuments.isEmpty {
            let docBlock = selectedDocuments.map { doc in
                "[Document: \(doc.filename)]\n\(doc.textPreview)"
            }.joined(separator: "\n\n")
            if systemContent.isEmpty {
                systemContent = "Context Documents:\n\(docBlock)"
            } else {
                systemContent += "\n\nContext Documents:\n\(docBlock)"
            }
        }
        if !systemContent.isEmpty {
            parts.append("<|im_start|>system\n\(systemContent)<|im_end|>")
        }

        // Conversation turns
        for message in messages {
            let role: String
            switch message.role {
            case .system: role = "system"
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .tool: role = "tool"
            }
            parts.append("<|im_start|>\(role)\n\(message.content)<|im_end|>")
        }

        // Assistant generation prompt — no content, just the opening tag
        parts.append("<|im_start|>assistant")
        return parts.joined(separator: "\n")
    }
}
