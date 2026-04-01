import Foundation

enum PromptBuilder {
    static func buildPrompt(messages: [ChatMessage], selectedDocuments: [ImportedDocument], systemPrompt: String) -> String {
        var sections: [String] = []
        let cleanSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSystem.isEmpty {
            sections.append("""
            System:
            \(cleanSystem)
            """)
        }
        if !selectedDocuments.isEmpty {
            let documents = selectedDocuments.map { doc in
                """
                [Document: \(doc.filename)]
                \(doc.textPreview)
                """
            }.joined(separator: "\n\n")
            sections.append("""
            Context Documents:
            \(documents)
            """)
        }
        let conversation = messages.map { message in
            let prefix: String
            switch message.role {
            case .system: prefix = "System"
            case .user: prefix = "User"
            case .assistant: prefix = "Assistant"
            case .tool: prefix = "Tool"
            }
            return "\(prefix): \(message.content)"
        }.joined(separator: "\n\n")
        sections.append(conversation)
        sections.append("Assistant:")
        return sections.joined(separator: "\n\n")
    }
}
