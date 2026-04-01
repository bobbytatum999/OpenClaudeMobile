import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                header
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                
                sessionPicker
                    .padding(.bottom, 8)
                
                messageList
                
                composer
            }
        }
        .navigationTitle("OpenClaude")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.newSession()
                } label: {
                    Image(systemName: "square.and.pencil.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.settings.selectedRuntime == .local ? (model.selectedLocalModel?.displayName ?? "No local model") : model.settings.remote.model)
                    .font(.system(.headline, design: .rounded))
                Text(model.settings.selectedRuntime == .local ? "On-device Inference" : "Remote Provider")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Runtime", selection: $model.settings.selectedRuntime) {
                ForEach(RuntimeSelection.allCases) { runtime in
                    Text(runtime.title).tag(runtime)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            .onChange(of: model.settings.selectedRuntime) {
                model.saveSettings()
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var sessionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.sessions) { session in
                    Button {
                        model.selectedSessionID = session.id
                    } label: {
                        Text(session.title)
                            .lineLimit(1)
                            .font(.subheadline.weight(session.id == model.selectedSessionID ? .semibold : .regular))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                if session.id == model.selectedSessionID {
                                    Capsule().fill(Color.accentColor.opacity(0.15))
                                } else {
                                    Capsule().fill(.regularMaterial)
                                }
                            }
                            .foregroundColor(session.id == model.selectedSessionID ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            model.deleteSession(session)
                        } label: {
                            Label("Delete Session", systemImage: "trash")
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
                LazyVStack(spacing: 16) {
                    let messages = model.selectedSession?.messages ?? []
                    if messages.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "message.and.waveform.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)
                            Text("Start a conversation")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 100)
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color.clear)
            .onChange(of: model.selectedSession?.updatedAt) {
                if let last = model.selectedSession?.messages.last?.id {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !selectedDocuments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(selectedDocuments) { document in
                            Label(document.filename, systemImage: "doc.text.fill")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1), in: Capsule())
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message OpenClaude...", text: $model.composingText, axis: .vertical)
                    .lineLimit(1...8)
                    .padding(12)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                
                Button {
                    Task { await model.sendMessage() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.isSending ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)))
                            .frame(width: 44, height: 44)
                            .shadow(color: model.isSending ? .clear : .purple.opacity(0.2), radius: 5, x: 0, y: 3)
                        
                        if model.isSending {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .disabled(model.isSending || model.composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(.bar)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -4)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var selectedDocuments: [ImportedDocument] {
        model.importedDocuments.filter { model.settings.selectedDocumentIDs.contains($0.id) }
    }
}
