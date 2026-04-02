import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(spacing: 4) {
            // Identity Header (Only for non-user roles)
            if message.role != .user {
                HStack(spacing: 6) {
                    if message.role == .assistant {
                        Circle()
                            .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 8, height: 8)
                        Text("OpenClaude")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(message.role.rawValue.uppercased())
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.leading, 8)
            }

            HStack(alignment: .bottom, spacing: 0) {
                if message.role == .user { Spacer(minLength: 40) }
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content.isEmpty ? "Thinking..." : message.content)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .rounded))
                        .lineSpacing(2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .background {
                            bubbleShape(for: message.role)
                                .fill(bubbleBackground(for: message.role))
                                .shadow(color: .black.opacity(message.role == .user ? 0.1 : 0.05), radius: 4, x: 0, y: 2)
                        }
                        .overlay {
                            if message.role != .user {
                                bubbleShape(for: message.role)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            }
                        }
                    
                    // Timestamp / Status (Optional detail)
                    Text(message.updatedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.placeholder)
                        .padding(.horizontal, 8)
                }
                
                if message.role != .user { Spacer(minLength: 40) }
            }
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
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.blue, Color(red: 0.3, green: 0.4, blue: 0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else if role == .assistant {
            return AnyShapeStyle(.ultraThinMaterial)
        } else {
            return AnyShapeStyle(.quaternary)
        }
    }
}
