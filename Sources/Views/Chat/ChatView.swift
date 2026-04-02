import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    messageList
                        .onTapGesture {
                            isFocused = false
                        }
                    
                    composer
                }
            }
            .navigationTitle("OpenClaude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    runtimeStatusView
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring()) {
                            model.newSession()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                sessionPicker
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var runtimeStatusView: some View {
        Menu {
            Picker("Runtime", selection: $model.settings.selectedRuntime) {
                ForEach(RuntimeSelection.allCases) { runtime in
                    Text(runtime.title).tag(runtime)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(model.settings.selectedRuntime == .local ? Color.green : Color.blue)
                    .frame(width: 6, height: 6)
                Text(model.settings.selectedRuntime == .local ? "Local" : "Remote")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.1)))
        }
    }

    private var sessionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(model.sessions) { session in
                    let isSelected = session.id == model.selectedSessionID
                    Button {
                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                            model.selectedSessionID = session.id
                        }
                    } label: {
                        Text(session.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.accentColor)
                                } else {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.05))
                                }
                            }
                            .foregroundColor(isSelected ? .white : .primary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation { model.deleteSession(session) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    let messages = model.selectedSession?.messages ?? []
                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .onChange(of: model.selectedSession?.updatedAt) {
                if let last = model.selectedSession?.messages.last?.id {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 100)
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("OpenClaude")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Spacer()
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message...", text: $model.composingText, axis: .vertical)
                    .focused($isFocused)
                    .lineLimit(1...10)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
                
                Button {
                    Task { 
                        isFocused = false
                        await model.sendMessage() 
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: 34, height: 34)
                }
                .disabled(model.isSending || model.composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
    }
}
