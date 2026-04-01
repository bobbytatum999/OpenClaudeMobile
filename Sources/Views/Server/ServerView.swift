import SwiftUI

struct ServerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Local API Server")
                            .font(.title3.weight(.semibold))
                        Text("Expose the app as a localhost OpenAI-compatible endpoint for Shortcuts, proxies, or companion tools.")
                            .foregroundStyle(.secondary)
                        TextField("Host", text: Binding(
                            get: { model.settings.server.host },
                            set: { model.settings.server.host = $0; model.saveSettings() }
                        ))
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Stepper(value: Binding(
                            get: { Int(model.settings.server.port) },
                            set: { model.settings.server.port = UInt16($0); model.saveSettings() }
                        ), in: 1024...65535) {
                            Text("Port: \(model.settings.server.port)")
                        }
                        Toggle("Start automatically on launch", isOn: Binding(
                            get: { model.settings.server.autoStart },
                            set: { model.settings.server.autoStart = $0; model.saveSettings() }
                        ))
                        HStack {
                            Button(model.isServerRunning ? "Stop Server" : "Start Server") {
                                Task {
                                    do {
                                        if model.isServerRunning {
                                            model.stopServer()
                                        } else {
                                            try await model.startServer()
                                        }
                                    } catch {
                                        model.statusLine = error.localizedDescription
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Text(model.serverBaseURL)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Endpoints")
                            .font(.title3.weight(.semibold))
                        endpoint("GET", "/health")
                        endpoint("GET", "/v1/models")
                        endpoint("POST", "/v1/chat/completions")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Server")
    }

    private func endpoint(_ method: String, _ path: String) -> some View {
        HStack {
            Text(method)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.tint.opacity(0.16), in: Capsule())
            Text(path)
                .font(.body.monospaced())
            Spacer()
        }
    }
}
