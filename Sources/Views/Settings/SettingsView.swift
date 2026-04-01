import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Remote Provider") {
                TextField("Base URL", text: Binding(
                    get: { model.settings.remote.baseURL },
                    set: { model.settings.remote.baseURL = $0; model.saveSettings() }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                TextField("API Key", text: Binding(
                    get: { model.settings.remote.apiKey },
                    set: { model.settings.remote.apiKey = $0; model.saveSettings() }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                TextField("Model", text: Binding(
                    get: { model.settings.remote.model },
                    set: { model.settings.remote.model = $0; model.saveSettings() }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                TextField("System Prompt", text: Binding(
                    get: { model.settings.remote.systemPrompt },
                    set: { model.settings.remote.systemPrompt = $0; model.saveSettings() }
                ), axis: .vertical)
                .lineLimit(3...8)

                Stepper(value: Binding(
                    get: { model.settings.remote.maxTokens },
                    set: { model.settings.remote.maxTokens = $0; model.saveSettings() }
                ), in: 128...8192, step: 64) {
                    Text("Max Tokens: \(model.settings.remote.maxTokens)")
                }
            }

            Section("Hugging Face") {
                SecureField("HF Token (optional for public models)", text: Binding(
                    get: { model.settings.huggingFaceToken },
                    set: { model.settings.huggingFaceToken = $0; model.saveSettings() }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Section("About") {
                LabeledContent("Build Target", value: "iOS 26+ • iPhone")
                LabeledContent("Reference Origin", value: "OpenClaude CLI archive")
                LabeledContent("Local Runtime", value: "GGUF via llama.cpp")
                LabeledContent("Remote Runtime", value: "OpenAI-compatible")
            }
        }
        .navigationTitle("Settings")
    }
}
