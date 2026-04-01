import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Imported Documents")
                            .font(.title3.weight(.semibold))
                        Text("Attach user-selected files to local or remote prompts. Text-like files and PDFs are previewed in-app.")
                            .foregroundStyle(.secondary)
                        Button {
                            importing = true
                        } label: {
                            Label("Import Files", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(model.importedDocuments) { document in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.filename)
                                        .font(.headline)
                                    Text(document.contentType)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("Attach", isOn: Binding(
                                    get: { model.settings.selectedDocumentIDs.contains(document.id) },
                                    set: { newValue in
                                        if newValue {
                                            model.settings.selectedDocumentIDs.insert(document.id)
                                        } else {
                                            model.settings.selectedDocumentIDs.remove(document.id)
                                        }
                                        model.saveSettings()
                                    }
                                ))
                                .labelsHidden()
                            }
                            Text(document.textPreview)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(14)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Files")
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.item, .text, .pdf, .sourceCode, .json],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.importDocuments(from: urls)
            case .failure(let error):
                model.statusLine = error.localizedDescription
            }
        }
    }
}
