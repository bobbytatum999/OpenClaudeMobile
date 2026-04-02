import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user { Spacer(minLength: 40) }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content.isEmpty ? "Thinking..." : message.content)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .background {
                        bubbleShape(for: message.role)
                            .fill(bubbleBackground(for: message.role))
                    }
                
                Text(message.updatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
            
            if message.role != .user { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 8)
    }

    private func bubbleShape(for role: ChatMessage.Role) -> some Shape {
        let isUser = role == .user
        return UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: isUser ? 18 : 4,
            bottomTrailingRadius: isUser ? 4 : 18,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    private func bubbleBackground(for role: ChatMessage.Role) -> AnyShapeStyle {
        if role == .user {
            return AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}
