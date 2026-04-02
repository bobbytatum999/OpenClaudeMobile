import SwiftUI
import MarkdownUI

// MARK: - ChatView

struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSessionMenu = false
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var renameSession: ChatSession? = nil
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sessionStrip
                Divider()
                messageList
                contextBar
                Divider()
                inputBar
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .background(Color(.systemBackground))
        }
        .sheet(item: $renameSession) { session in
            RenameSessionSheet(session: session, text: $renameText) { newTitle in
                model.renameSession(session, to: newTitle)
            }
        }
        .sheet(isPresented: $model.showingExportSheet) {
            ExportSheet(content: model.exportContent)
        }
    }

    // MARK: - Session Strip

    private var sessionStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: model.newSession) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("New chat")

                    ForEach(model.sessions) { session in
                        let isSelected = session.id == model.selectedSessionID
                        SessionChip(session: session, isSelected: isSelected) {
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                                model.selectedSessionID = session.id
                            }
                            model.haptic(.light)
                        } onDelete: {
                            withAnimation { model.deleteSession(session) }
                        } onPin: {
                            model.pinSession(session)
                        } onRename: {
                            renameText = session.title
                            renameSession = session
                        }
                        .id(session.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: model.selectedSessionID) { _, id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if model.selectedSession?.messages.isEmpty != false {
                        emptyState
                    } else {
                        ForEach(model.selectedSession?.messages ?? []) { message in
                            MessageRow(message: message)
                                .id(message.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    Color.clear.frame(height: 16).id("bottom")
                }
                .padding(.vertical, 8)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.selectedSession?.messages.count)
            }
            .onChange(of: model.selectedSession?.messages.last?.content) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom")
                }
            }
            .onChange(of: model.selectedSessionID) { _, _ in
                proxy.scrollTo("bottom")
            }
        }
    }

    // MARK: - Context Bar

    private var contextBar: some View {
        HStack(spacing: 10) {
            // Token fill bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill)).frame(height: 4)
                    Capsule()
                        .fill(contextFillColor)
                        .frame(width: geo.size.width * min(model.contextFill, 1.0), height: 4)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: model.contextFill)
                }
            }
            .frame(height: 4)

            Text("~\(model.estimatedTokenCount) tok")
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospacedDigit()

            if let stats = model.generationStats, stats.tokensPerSecond > 0 {
                Text(String(format: "%.1f t/s", stats.tokensPerSecond))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .transition(.opacity)
            }

            // Runtime pill
            Button {
                withAnimation {
                    model.settings.selectedRuntime = model.settings.selectedRuntime == .local ? .remote : .local
                    model.saveSettings()
                    model.haptic(.light)
                }
            } label: {
                Label(model.settings.selectedRuntime.title,
                      systemImage: model.settings.selectedRuntime == .local ? "cpu.fill" : "cloud.fill")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(model.settings.selectedRuntime == .local ? Color.green.opacity(0.15) : Color.blue.opacity(0.12))
                    .foregroundColor(model.settings.selectedRuntime == .local ? .green : .blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private var contextFillColor: Color {
        let f = model.contextFill
        if f < 0.6 { return .green }
        if f < 0.85 { return .orange }
        return .red
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if model.isSending {
                // Stop button banner
                Button(action: model.stopGeneration) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                        Text("Stop generating")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message…", text: $model.composingText, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .font(.body)
                    .onSubmit {
                        guard !model.isSending else { return }
                        Task { await model.sendMessage() }
                    }
                    .submitLabel(.send)

                Button {
                    model.haptic(.light)
                    Task { await model.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(canSend ? .accentColor : Color(.systemFill))
                }
                .disabled(!canSend)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.isSending)
    }

    private var canSend: Bool {
        !model.composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isSending
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 30))
                    .foregroundColor(.accentColor)
            }
            VStack(spacing: 6) {
                Text("OpenClaude")
                    .font(.title2.bold())
                Text("Ask anything. Run locally or via API.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if model.settings.selectedRuntime == .local && model.installedModels.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("No models installed — go to Models tab to download one")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 4) {
                Image(systemName: "cpu.fill")
                    .font(.footnote)
                    .foregroundColor(.accentColor)
                Text("OpenClaude")
                    .font(.headline.bold())
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Regenerate
            if let session = model.selectedSession, session.messages.last?.role == .assistant, !model.isSending {
                Button {
                    Task { await model.regenerateLastResponse() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Regenerate")
            }
            // Export
            if model.selectedSession?.messages.isEmpty == false {
                Button { model.exportCurrentSession() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export chat")
            }
        }
    }
}

// MARK: - SessionChip

struct SessionChip: View {
    let session: ChatSession
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    let onRename: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .orange)
                }
                Text(session.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule().fill(Color.accentColor)
                } else {
                    Capsule().fill(Color(.secondarySystemFill))
                }
            }
            .foregroundColor(isSelected ? .white : .primary.opacity(0.75))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onPin() } label: {
                Label(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin")
            }
            Button { onRename() } label: {
                Label("Rename", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - MessageRow

struct MessageRow: View {
    @EnvironmentObject var model: AppModel
    let message: ChatMessage
    @State private var showActions = false

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Bubble
                messageBubble
                    .contextMenu { messageActions }

                // Typing indicator for empty assistant msg
                if !isUser && message.content.isEmpty && model.isSending {
                    TypingIndicator()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var messageBubble: some View {
        if !message.content.isEmpty {
            Group {
                if isUser {
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Markdown(message.content)
                        .markdownTheme(.openClaude)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.isError ? Color.red.opacity(0.1) : Color(.secondarySystemBackground))
                        .foregroundColor(message.isError ? .red : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var messageActions: some View {
        Button {
            UIPasteboard.general.string = message.content
            model.haptic(.light)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        if !isUser {
            Button {
                Task { await model.regenerateLastResponse() }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
        }
        Divider()
        Button(role: .destructive) {
            withAnimation { model.deleteMessage(message) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase: Int = 0
    let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.3 : 0.85)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: phase)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

// MARK: - Rename Sheet

struct RenameSessionSheet: View {
    let session: ChatSession
    @Binding var text: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Session title", text: $text)
                    .autocorrectionDisabled(false)
            }
            .navigationTitle("Rename Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { onConfirm(t) }
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(160)])
    }
}

// MARK: - Export Sheet

struct ExportSheet: View {
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .navigationTitle("Export Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: content)
                }
            }
        }
    }
}

// MARK: - Markdown Theme

extension Theme {
    static let openClaude = Theme.gitHub
        .text {
            FontSize(.em(1))
            ForegroundColor(.primary)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.9))
            BackgroundColor(Color(.systemFill))
        }
        .codeBlock { (configuration: CodeBlockConfiguration) in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(configuration.language ?? "code")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = configuration.content
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .relativeLineSpacing(.em(0.25))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.88))
                        }
                        .padding(12)
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .markdownMargin(top: 0, bottom: 16)
        }
}
