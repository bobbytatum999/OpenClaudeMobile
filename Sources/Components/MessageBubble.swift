import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role != .assistant { Spacer(minLength: 32) }
            
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(Circle())
                    .shadow(color: .indigo.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                if message.role == .system || message.role == .tool {
                    Text(message.role.rawValue.capitalized)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                
                Text(message.content.isEmpty ? "..." : message.content)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(message.role == .user ? .white : .primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                if message.role == .user {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 4,
                        topTrailingRadius: 20,
                        style: .continuous
                    )
                    .fill(LinearGradient(colors: [Color.blue, Color.purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .blue.opacity(0.25), radius: 5, x: 0, y: 3)
                } else if message.role == .assistant {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20,
                        bottomLeadingRadius: 4,
                        bottomTrailingRadius: 20,
                        topTrailingRadius: 20,
                        style: .continuous
                    )
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 20,
                            bottomLeadingRadius: 4,
                            bottomTrailingRadius: 20,
                            topTrailingRadius: 20,
                            style: .continuous
                        )
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
            
            if message.role == .assistant { Spacer(minLength: 32) }
        }
    }
}
