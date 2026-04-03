import SwiftUI
import MarkdownUI
import UIKit

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user { Spacer(minLength: 40) }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Group {
                    if message.role == .assistant || message.role == .tool {
                        Markdown(message.content.isEmpty ? "Thinking..." : message.content)
                            .markdownTheme(.gitHub)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        Text(message.content.isEmpty ? "Thinking..." : message.content)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                    }
                }
                .textSelection(.enabled)
                .font(.system(.body, design: .rounded))
                .background {
                    bubbleShape(for: message.role)
                        .fill(bubbleBackground(for: message.role))
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(6)
                            .background(.thinMaterial, in: Circle())
                    }
                    .padding(6)
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
        } else if role == .tool {
            return AnyShapeStyle(Color.orange.opacity(0.15))
        } else {
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}
