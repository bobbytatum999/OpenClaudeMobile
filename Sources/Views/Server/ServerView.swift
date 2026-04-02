import SwiftUI

struct ServerView: View {
    @EnvironmentObject var model: AppModel
    @State private var copiedURL = false

    var body: some View {
        NavigationStack {
            List {
                // Status card
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(model.isServerRunning ? Color.green.opacity(0.15) : Color(.systemFill))
                                .frame(width: 52, height: 52)
                            Image(systemName: model.isServerRunning ? "server.rack" : "server.rack")
                                .font(.title2)
                                .foregroundColor(model.isServerRunning ? .green : .secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.isServerRunning ? "Server Running" : "Server Stopped")
                                .font(.headline)
                                .foregroundColor(model.isServerRunning ? .green : .primary)
                            Text(model.statusLine)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        // Live indicator dot
                        if model.isServerRunning {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)
                                .modifier(PulsingModifier())
                        }
                    }
                    .padding(.vertical, 4)
                }

                // URL row
                if model.isServerRunning {
                    Section("Endpoint") {
                        Button {
                            UIPasteboard.general.string = model.serverBaseURL
                            copiedURL = true
                            model.haptic(.light)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedURL = false }
                        } label: {
                            HStack {
                                Image(systemName: copiedURL ? "checkmark.circle.fill" : "doc.on.doc")
                                    .foregroundColor(copiedURL ? .green : .accentColor)
                                    .animation(.spring(response: 0.3), value: copiedURL)
                                Text(model.serverBaseURL)
                                    .font(.body.monospaced())
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Configuration
                Section("Configuration") {
                    LabeledContent("Host") {
                        TextField("127.0.0.1", text: $model.settings.server.host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Port") {
                        TextField("8080", value: $model.settings.server.port, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Auto-Start on Launch", isOn: $model.settings.server.autoStart)
                        .onChange(of: model.settings.server.autoStart) { _, _ in model.saveSettings() }
                }
                .disabled(model.isServerRunning)

                // Routes reference
                Section("Available Routes") {
                    ForEach(routes, id: \.path) { route in
                        HStack(spacing: 10) {
                            Text(route.method)
                                .font(.caption.monospaced().bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(route.method == "GET" ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                                .foregroundColor(route.method == "GET" ? .blue : .green)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.path).font(.caption.monospaced())
                                Text(route.desc).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Start / Stop
                Section {
                    if model.isServerRunning {
                        Button(role: .destructive) {
                            Task { await model.stopServer() }
                        } label: {
                            Label("Stop Server", systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } else {
                        Button {
                            Task {
                                do { try await model.startServer() }
                                catch { model.statusLine = error.localizedDescription }
                            }
                        } label: {
                            Label("Start Server", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .navigationTitle("Local API Server")
        }
    }

    let routes = [
        (method: "GET",  path: "/health",              desc: "Health check"),
        (method: "GET",  path: "/v1/models",           desc: "List available models"),
        (method: "POST", path: "/v1/chat/completions", desc: "Chat completions (streaming supported)"),
    ]
}

struct PulsingModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scale = 1.5
                }
            }
    }
}
