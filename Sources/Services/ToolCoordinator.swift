import Foundation

struct ToolCall: Codable, Sendable {
    let name: String
    let arguments: [String: String]
}

struct ToolResult: Sendable {
    let name: String
    let output: String
    let isError: Bool
}

struct ToolDefinition: Sendable {
    let name: String
    let description: String
    let argumentSchema: [String: String]
    let handler: @Sendable ([String: String]) async throws -> String
}

enum ToolCoordinatorError: LocalizedError {
    case unknownTool(String)
    case invalidToolCall

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .invalidToolCall:
            return "Could not parse tool call JSON."
        }
    }
}

actor ToolCoordinator {
    private var tools: [String: ToolDefinition] = [:]

    init(tools: [ToolDefinition] = []) {
        for tool in tools {
            self.tools[tool.name] = tool
        }
    }

    func register(_ tool: ToolDefinition) {
        tools[tool.name] = tool
    }

    func allTools() -> [ToolDefinition] {
        Array(tools.values).sorted { $0.name < $1.name }
    }

    /// Expected format in model output:
    /// <tool_call>{"name":"search_docs","arguments":{"query":"..."}}</tool_call>
    func parseToolCall(from text: String) -> ToolCall? {
        guard let start = text.range(of: "<tool_call>"),
              let end = text.range(of: "</tool_call>"),
              start.upperBound <= end.lowerBound else { return nil }
        let payload = String(text[start.upperBound..<end.lowerBound])
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ToolCall.self, from: data)
    }

    func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = tools[call.name] else {
            return ToolResult(name: call.name, output: ToolCoordinatorError.unknownTool(call.name).localizedDescription, isError: true)
        }
        do {
            let output = try await tool.handler(call.arguments)
            return ToolResult(name: call.name, output: output, isError: false)
        } catch {
            return ToolResult(name: call.name, output: error.localizedDescription, isError: true)
        }
    }
}
