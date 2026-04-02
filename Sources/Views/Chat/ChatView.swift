import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                // Main Background
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                // Background Gradient Glow
                VStack {
                    LinearGradient(colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 300)
                    Spacer()
                }
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
                    .overlay(Alignment.bottom) {
                        Divider()
                    }
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
            .onChange(of: model.settings.selectedRuntime) {
                model.saveSettings()
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
            .background(.capsule.fill.opacity(0.1))
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
                                        .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
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
                            model.deleteSession(session)
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
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
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
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.1), .purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            VStack(spacing: 8) {
                Text("OpenClaude")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Your private, on-device AI assistant.\nPowered by Llama-3 & Claude.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            
            VStack(spacing: 12) {
                if !selectedDocuments.isEmpty {
                    documentTray
                }
                
                HStack(alignment: .bottom, spacing: 12) {
                    // Attachment Button
                    Button {} label: {
                        Image(systemName: "paperclip")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 10)
                    
                    TextField("Message...", text: $model.composingText, axis: .vertical)
                        .focused($isFocused)
                        .lineLimit(1...10)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    
                    sendButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .background(.ultraThinMaterial)
        }
    }

    private var documentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedDocuments) { document in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.fill")
                        Text(document.filename)
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                    .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var sendButton: some View {
        Button {
            Task { 
                isFocused = false
                await model.sendMessage() 
            }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .resizable()
                .frame(width: 34, height: 34)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.isSending ? Color.gray : Color.accentColor)
                .background(Circle().fill(.white).padding(2))
        }
        .disabled(model.isSending || model.composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .padding(.bottom, 4)
    }

    private var selectedDocuments: [ImportedDocument] {
        model.importedDocuments.filter { model.settings.selectedDocumentIDs.contains($0.id) }
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
