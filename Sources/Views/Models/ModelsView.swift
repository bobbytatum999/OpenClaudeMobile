import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedForDownload: HuggingFaceModelSummary?

    var body: some View {
        NavigationStack {
            List {
                Section("Installed Models") {
                    if model.installedModels.isEmpty {
                        Text("No models installed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.installedModels) { installed in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(installed.displayName)
                                        .font(.headline)
                                    Text(installed.repoID)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.settings.selectedLocalModelID == installed.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.green)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.settings.selectedLocalModelID = installed.id
                                model.saveSettings()
                            }
                        }
                    }
                }

                Section("Available on Hugging Face") {
                    if model.isSearchingModels {
                        HStack {
                            ProgressView()
                            Text("Searching...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if model.searchedModels.isEmpty {
                        Text("Search for models above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.searchedModels) { hf in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hf.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(hf.id)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Label("\(hf.likes ?? 0)", systemImage: "heart.fill")
                                    Label("\(hf.downloads ?? 0)", systemImage: "arrow.down.circle.fill")
                                    Spacer()
                                    Button("Download") {
                                        selectedForDownload = hf
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .font(.caption2)
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if model.isDownloadingModel, let progress = model.downloadProgress {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Downloading...")
                                .font(.caption.weight(.semibold))
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Models")
            .searchable(text: $model.searchQuery, prompt: "Search Hugging Face")
            .onSubmit(of: .search) {
                Task { await model.searchHuggingFace() }
            }
            .sheet(item: $selectedForDownload) { hf in
                GGUFPickerSheet(summary: hf) { sibling in
                    selectedForDownload = nil
                    Task { await model.install(hf, sibling: sibling) }
                }
            }
        }
    }
}

struct GGUFPickerSheet: View {
    let summary: HuggingFaceModelSummary
    let onSelect: (HuggingFaceSibling) -> Void
    @Environment(\.dismiss) private var dismiss

    var ggufFiles: [HuggingFaceSibling] {
        summary.siblings.filter { $0.rfilename.lowercased().hasSuffix(".gguf") }
    }

    var body: some View {
        NavigationStack {
            Group {
                if ggufFiles.isEmpty {
                    ContentUnavailableView("No GGUF Files", systemImage: "exclamationmark.triangle", description: Text("This repository has no downloadable GGUF files."))
                } else {
                    List(ggufFiles, id: \.rfilename) { sibling in
                        Button {
                            onSelect(sibling)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sibling.filename)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                if let size = sibling.size {
                                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Pick GGUF File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
