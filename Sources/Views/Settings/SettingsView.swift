import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAPIKey = false
    @State private var showHFToken = false

    var body: some View {
        NavigationStack {
            Form {
                // Runtime selection
                Section("Runtime") {
                    Picker("Default Runtime", selection: $model.settings.selectedRuntime) {
                        ForEach(RuntimeSelection.allCases) { r in
                            Label(r.title, systemImage: r == .local ? "cpu.fill" : "cloud.fill")
                                .tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.settings.selectedRuntime) { _, _ in model.saveSettings() }
                }

                // Remote / API
                Section {
                    LabeledContent("Provider URL") {
                        TextField("https://api.anthropic.com/v1", text: $model.settings.remote.baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Model") {
                        TextField("claude-3-5-sonnet-20240620", text: $model.settings.remote.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Label("API Key", systemImage: "key.fill")
                        Spacer()
                        Group {
                            if showAPIKey {
                                TextField("sk-…", text: $model.settings.remote.apiKey)
                            } else {
                                SecureField("sk-…", text: $model.settings.remote.apiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        Button { showAPIKey.toggle() } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                    LabeledContent("Temperature") {
                        Slider(value: $model.settings.remote.temperature, in: 0...2, step: 0.05)
                            .frame(width: 130)
                        Text(String(format: "%.2f", model.settings.remote.temperature))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 36)
                    }
                    LabeledContent("Max Tokens") {
                        TextField("4096", value: $model.settings.remote.maxTokens, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Remote / API")
                } footer: {
                    Text("Compatible with any OpenAI-format provider including Anthropic, Groq, Ollama, and LM Studio.")
                }

                // System prompt
                Section("System Prompt") {
                    TextEditor(text: $model.settings.remote.systemPrompt)
                        .frame(minHeight: 80)
                        .font(.body)
                }

                // HuggingFace
                Section {
                    HStack {
                        Label("HF Token", systemImage: "person.badge.key.fill")
                        Spacer()
                        Group {
                            if showHFToken {
                                TextField("hf_…", text: $model.settings.huggingFaceToken)
                            } else {
                                SecureField("hf_… (optional, for gated models)", text: $model.settings.huggingFaceToken)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        Button { showHFToken.toggle() } label: {
                            Image(systemName: showHFToken ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("HuggingFace")
                } footer: {
                    Text("Required for gated or private model downloads.")
                }

                // Behaviour
                Section("Behaviour") {
                    Toggle(isOn: $model.settings.hapticFeedback) {
                        Label("Haptic Feedback", systemImage: "waveform")
                    }
                    .onChange(of: model.settings.hapticFeedback) { _, _ in model.saveSettings() }
                }

                // App info
                Section("About") {
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com/bobbytatum999/OpenClaudeMobile")!) {
                        Label("GitHub Repository", systemImage: "link")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        model.saveSettings()
                        model.haptic(.success)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
