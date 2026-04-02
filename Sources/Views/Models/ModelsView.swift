import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedForInstall: HuggingFaceModelSummary? = nil
    @State private var selectedForDetail: HuggingFaceModelSummary? = nil

    var body: some View {
        NavigationStack {
            List {
                // Download progress banner
                if model.isDownloadingModel {
                    downloadBanner
                }

                // Installed models
                if !model.installedModels.isEmpty {
                    Section {
                        ForEach(model.installedModels) { installed in
                            InstalledModelRow(installed: installed)
                        }
                        .onDelete { offsets in
                            offsets.forEach { i in model.uninstallModel(model.installedModels[i]) }
                        }
                    } header: {
                        Text("Installed (\(model.installedModels.count))")
                    }
                }

                // Search
                Section {
                    if model.isSearchingModels {
                        HStack {
                            Spacer()
                            ProgressView().padding(.vertical, 8)
                            Spacer()
                        }
                    } else if model.searchedModels.isEmpty {
                        searchEmptyState
                    } else {
                        ForEach(model.searchedModels) { hf in
                            HFModelRow(hf: hf) {
                                selectedForDetail = hf
                            }
                        }
                    }
                } header: {
                    Text("Search Results")
                }
            }
            .navigationTitle("Models")
            .searchable(text: $model.searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search HuggingFace…")
            .onSubmit(of: .search) {
                Task { await model.searchHuggingFace() }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await model.searchHuggingFace() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(model.isSearchingModels)
                }
            }
            .task { if model.searchedModels.isEmpty { await model.searchHuggingFace() } }
            .sheet(item: $selectedForDetail) { hf in
                ModelDetailSheet(hf: hf) { sibling in
                    selectedForDetail = nil
                    Task { await model.install(hf, sibling: sibling) }
                }
            }
        }
    }

    // MARK: - Download Banner

    private var downloadBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloading Model")
                        .font(.subheadline.bold())
                    if let filename = model.downloadingFilename {
                        Text(filename)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let progress = model.downloadProgress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundColor(.accentColor)
                }
            }
            ProgressView(value: model.downloadProgress ?? 0)
                .tint(.accentColor)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.accentColor.opacity(0.06))
    }

    // MARK: - Search empty state

    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.4))
            Text("Search for GGUF models on HuggingFace")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Search Now") {
                Task { await model.searchHuggingFace() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowBackground(Color.clear)
    }
}

// MARK: - InstalledModelRow

struct InstalledModelRow: View {
    @EnvironmentObject var model: AppModel
    let installed: InstalledModel
    var isSelected: Bool { model.settings.selectedLocalModelID == installed.id }

    var body: some View {
        Button {
            model.settings.selectedLocalModelID = installed.id
            model.settings.selectedRuntime = .local
            model.saveSettings()
            model.haptic(.light)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)
                    .animation(.spring(response: 0.3), value: isSelected)

                VStack(alignment: .leading, spacing: 3) {
                    Text(installed.displayName)
                        .font(.subheadline.bold())
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        QuantBadge(tier: installed.qualityTier, label: installed.quantLabel ?? "")
                        Text(installed.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                model.uninstallModel(installed)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - HFModelRow

struct HFModelRow: View {
    let hf: HuggingFaceModelSummary
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(hf.displayName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(hf.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let tag = hf.pipelineTag {
                            Text(tag)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1))
                                .foregroundColor(.purple)
                                .clipShape(Capsule())
                        }
                        if let dl = hf.downloads {
                            Label("\(formatCount(dl))", systemImage: "arrow.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let likes = hf.likes {
                            Label("\(formatCount(likes))", systemImage: "heart.fill")
                                .font(.caption2)
                                .foregroundColor(.pink)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Model Detail Sheet

struct ModelDetailSheet: View {
    let hf: HuggingFaceModelSummary
    let onInstall: (HuggingFaceSibling) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Header
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hf.id)
                            .font(.headline)
                        if let tag = hf.pipelineTag {
                            Text(tag.capitalized)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.purple.opacity(0.12))
                                .foregroundColor(.purple)
                                .clipShape(Capsule())
                        }
                        HStack(spacing: 16) {
                            if let dl = hf.downloads {
                                Label("\(dl) downloads", systemImage: "arrow.down.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let likes = hf.likes {
                                Label("\(likes) likes", systemImage: "heart")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let modified = hf.lastModified {
                            Text("Updated \(modified.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // GGUF files
                if hf.ggufSiblings.isEmpty {
                    Section("No GGUF Files") {
                        Text("This repo has no .gguf files available for download.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Select Quantization") {
                        ForEach(hf.ggufSiblings, id: \.rfilename) { sibling in
                            Button {
                                dismiss()
                                onInstall(sibling)
                            } label: {
                                HStack(spacing: 12) {
                                    QuantBadge(tier: sibling.qualityTier, label: sibling.quantLabel ?? "?")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(sibling.filename)
                                            .font(.subheadline)
                                            .lineLimit(2)
                                        Text(sibling.formattedSize)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Model Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - QuantBadge

struct QuantBadge: View {
    let tier: QuantTier
    let label: String

    var bgColor: Color {
        switch tier {
        case .fast: return .orange
        case .balanced: return .yellow
        case .quality: return .green
        case .max: return .blue
        case .unknown: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: tier.systemImage)
                .font(.caption2)
            Text(label.isEmpty ? tier.rawValue : label)
                .font(.caption2.bold())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(bgColor.opacity(0.15))
        .foregroundColor(bgColor)
        .clipShape(Capsule())
    }
}
