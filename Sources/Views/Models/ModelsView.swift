import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var isSearching = false

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
                            }
                        }
                    }
                }
                
                Section("Available on Hugging Face") {
                    ForEach(model.hfModels) { hf in
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
                                    // Implementation in AppModel
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
            .navigationTitle("Models")
            .searchable(text: $searchText)
        }
    }
}
