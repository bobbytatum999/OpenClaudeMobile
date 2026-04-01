import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                searchCard
                if let details = model.selectedModelDetails {
                    detailCard(details)
                }
                installedCard
            }
            .padding()
        }
        .navigationTitle("Models")
        .task {
            if model.searchedModels.isEmpty {
                await model.searchHuggingFace()
            }
        }
    }

    private var searchCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hugging Face GGUF Browser")
                    .font(.title3.weight(.semibold))
                TextField("Search models", text: $model.searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                HStack {
                    Button {
                        Task { await model.searchHuggingFace() }
                    } label: {
                        if model.isSearchingModels {
                            ProgressView()
                        } else {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Text("\(model.searchedModels.count) result(s)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.searchedModels.prefix(8)) { item in
                    Button {
                        model.selectedModelDetails = item
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.id)
                                    .font(.headline)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 10) {
                                    if let tag = item.pipelineTag {
                                        Label(tag, systemImage: "tag.fill")
                                    }
                                    if let downloads = item.downloads {
                                        Label("\(downloads)", systemImage: "arrow.down.circle")
                                    }
                                    Text("GGUF \(item.ggufFiles.count)")
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(model.selectedModelDetails?.id == item.id ? .tint.opacity(0.16) : .regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func detailCard(_ details: HuggingFaceModelSummary) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(details.id)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 14) {
                    Label("GGUF: \(details.ggufFiles.count)", systemImage: "shippingbox.fill")
                    Label("Likes: \(details.likes ?? 0)", systemImage: "heart.fill")
                    Label(details.privateRepo ? "Private" : "Public", systemImage: details.privateRepo ? "lock.fill" : "lock.open.fill")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                if details.ggufFiles.isEmpty {
                    Text("No GGUF files were advertised in this repo's file list.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(details.ggufFiles) { sibling in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sibling.filename)
                                    .font(.headline)
                                Text(sibling.rfilename)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button {
                                Task { await model.install(details, sibling: sibling) }
                            } label: {
                                if model.isDownloadingModel {
                                    ProgressView()
                                } else {
                                    Label("Install", systemImage: "arrow.down.to.line")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }

    private var installedCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Installed Local Models")
                    .font(.title3.weight(.semibold))
                if model.installedModels.isEmpty {
                    Text("No GGUF models installed yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.installedModels) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.filename)
                                    .font(.headline)
                                Text(item.repoID)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(model.settings.selectedLocalModelID == item.id ? "Selected" : "Use") {
                                model.settings.selectedRuntime = .local
                                model.settings.selectedLocalModelID = item.id
                                model.saveSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(model.settings.selectedLocalModelID == item.id ? .green : .accentColor)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }
}
