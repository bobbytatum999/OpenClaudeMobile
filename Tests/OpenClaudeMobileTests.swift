import XCTest
@testable import OpenClaudeMobile

final class OpenClaudeMobileTests: XCTestCase {
    func testPromptBuilderIncludesDocumentsAndAssistantCue() {
        let messages = [ChatMessage(role: .user, content: "Hello")]
        let docs = [DocumentChunk(documentID: UUID(), filename: "notes.txt", text: "Important project context", score: 1)]
        let prompt = PromptBuilder.buildPrompt(
            messages: messages,
            systemPrompt: "System prompt",
            documentChunks: docs,
            tools: [],
            modelHint: "qwen2.5"
        )
        XCTAssertTrue(prompt.contains("Important project context"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant"))
    }

    func testToolParserParsesJSONCall() {
        let parser = ToolCallParser()
        let json = """
        {"tool_call":{"name":"search_documents","arguments":{"query":"roadmap"}}}
        """
        let call = parser.parse(text: json)
        XCTAssertEqual(call?.name, "search_documents")
        XCTAssertEqual(call?.arguments["query"], "roadmap")
    }
}
