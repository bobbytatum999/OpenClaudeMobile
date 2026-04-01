import XCTest
@testable import OpenClaudeMobile

final class OpenClaudeMobileTests: XCTestCase {
    func testPromptBuilderIncludesDocuments() {
        let messages = [ChatMessage(role: .user, content: "Hello")]
        let docs = [ImportedDocument(filename: "notes.txt", localPath: "/tmp/notes.txt", contentType: "text/plain", textPreview: "Important project context")]
        let prompt = PromptBuilder.buildPrompt(messages: messages, selectedDocuments: docs, systemPrompt: "System prompt")
        XCTAssertTrue(prompt.contains("Important project context"))
        XCTAssertTrue(prompt.contains("Assistant:"))
    }
}
