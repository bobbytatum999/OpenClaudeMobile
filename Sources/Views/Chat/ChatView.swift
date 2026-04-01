import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            header
            sessionPicker
            messageList
            composer
        }
        .padding()
        .navigationTitle("OpenClaude")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.newSession()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
    }

    private var header: some View {
        GlassCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Runtime")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(model.settings.selectedRuntime == .local ? (model.selectedLocalModel?.displayName ?? "No local model selected") : model.settings.remote.model)
                        .font(.headline)
                    Text(model.settings.selectedRuntime == .local ? "On-device GGUF inference" : "OpenAI-compatible remote provider")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Runtime", selection: $model.settings.selectedRuntime) {
                    ForEach(RuntimeSelection.allCases) { runtime in
                        Text(runtime.title).tag(runtime)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .onChange(of: model.settings.selectedRuntime) {
                    model.saveSettings()
                }
            }
        }
    }

    private var sessionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.sessions) { session in
                    Button {
                        model.selectedSessionID = session.id
                    } label: {
                        Text(session.title)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background {
                                if session.id == model.selectedSessionID {
                                    Capsule().fill(.tint.opacity(0.18))
                                } else {
                                    Capsule().fill(.thinMaterial)
                                }
                            }
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
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.selectedSession?.messages ?? []) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
            }
            .background(.clear)
            .onChange(of: model.selectedSession?.messages.count ?? 0) {
                if let last = model.selectedSession?.messages.last?.id {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if !selectedDocuments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(selectedDocuments) { document in
                                Label(document.filename, systemImage: "doc.text")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.regularMaterial, in: Capsule())
                            }
                        }
                    }
                }
                TextEditor(text: $model.composingText)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                HStack {
                    Text(model.settings.selectedRuntime == .local ? "Local model will receive a rendered conversation prompt." : "Remote provider will receive OpenAI-compatible chat messages.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await model.sendMessage() }
                    } label: {
                        if model.isSending {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Label("Send", systemImage: "arrow.up.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSending || model.composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var selectedDocuments: [ImportedDocument] {
        model.importedDocuments.filter { model.settings.selectedDocumentIDs.contains($0.id) }
    }
}
