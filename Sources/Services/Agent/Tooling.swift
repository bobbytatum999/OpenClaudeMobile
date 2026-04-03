import Foundation

struct ToolDefinition: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let description: String
    let parameters: [String]
}

protocol ToolExecutable: Sendable {
    var definition: ToolDefinition { get }
    func run(arguments: [String: String]) async throws -> String
}

actor ToolRegistry {
    private var tools: [String: any ToolExecutable] = [:]

    func register(_ tool: any ToolExecutable) {
        tools[tool.definition.name] = tool
    }

    func definitions() -> [ToolDefinition] {
        tools.values.map(\.definition).sorted { $0.name < $1.name }
    }

    func execute(_ call: ToolCall) async -> ToolExecutionEvent {
        guard let tool = tools[call.name] else {
            return ToolExecutionEvent(toolName: call.name, input: call.arguments, output: "Tool not found: \(call.name)", isError: true)
        }
        do {
            let output = try await tool.run(arguments: call.arguments)
            return ToolExecutionEvent(toolName: call.name, input: call.arguments, output: output, isError: false)
        } catch {
            return ToolExecutionEvent(toolName: call.name, input: call.arguments, output: error.localizedDescription, isError: true)
        }
    }
}

struct ToolCallParser {
    /// Expected payload format in model output:
    /// {"tool_call":{"name":"search_notes","arguments":{"query":"..."}}}
    func parse(text: String) -> ToolCall? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let jsonSlice = String(text[start...end])
        guard let data = jsonSlice.data(using: .utf8) else { return nil }

        struct Envelope: Decodable {
            struct ToolEnvelope: Decodable {
                let name: String
                let arguments: [String: String]
            }
            let tool_call: ToolEnvelope
        }

        guard let decoded = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        return ToolCall(name: decoded.tool_call.name, arguments: decoded.tool_call.arguments)
    }
}

actor ToolCoordinator {
    private let parser = ToolCallParser()
    private let registry: ToolRegistry

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    func availableTools() async -> [ToolDefinition] {
        await registry.definitions()
    }

    func attemptToolExecution(from assistantText: String) async -> ToolExecutionEvent? {
        guard let call = parser.parse(text: assistantText) else { return nil }
        return await registry.execute(call)
    }
}
