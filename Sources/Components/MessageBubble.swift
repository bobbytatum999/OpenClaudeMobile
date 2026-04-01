import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role != .assistant { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.content.isEmpty ? "…" : message.content)
                    .textSelection(.enabled)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: message.role == .assistant ? .leading : .trailing)
            .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if message.role == .assistant { Spacer(minLength: 24) }
        }
    }

    private var label: String {
        switch message.role {
        case .system: return "System"
        case .user: return "You"
        case .assistant: return "Assistant"
        case .tool: return "Tool"
        }
    }

    private var background: some ShapeStyle {
        switch message.role {
        case .user:
            return AnyShapeStyle(.tint.opacity(0.16))
        case .assistant:
            return AnyShapeStyle(.thinMaterial)
        case .system, .tool:
            return AnyShapeStyle(.secondary.opacity(0.12))
        }
    }
}
