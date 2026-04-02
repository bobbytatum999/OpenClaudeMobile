import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @EnvironmentObject var model: AppModel
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            Group {
                if model.importedDocuments.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(model.importedDocuments) { doc in
                                DocumentRow(doc: doc)
                            }
                            .onDelete { offsets in
                                offsets.forEach { i in
                                    let doc = model.importedDocuments[i]
                                    model.settings.selectedDocumentIDs.remove(doc.id)
                                    model.importedDocuments.remove(at: i)
                                }
                                model.persistDocuments()
                                model.saveSettings()
                            }
                        } header: {
                            if !model.settings.selectedDocumentIDs.isEmpty {
                                Text("\(model.settings.selectedDocumentIDs.count) selected for context")
                                    .foregroundColor(.accentColor)
                            }
                        } footer: {
                            Text("Selected documents are included in every message you send.")
                        }
                    }
                }
            }
            .navigationTitle("Files")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                if !model.settings.selectedDocumentIDs.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Clear Selection") {
                            model.settings.selectedDocumentIDs.removeAll()
                            model.saveSettings()
                        }
                        .font(.caption)
                    }
                }
            }
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: [.text, .pdf, .plainText, .utf8PlainText,
                                                .commaSeparatedText, .json,
                                                UTType("public.markdown") ?? .plainText,
                                                UTType("com.apple.xcode.swift") ?? .plainText],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): model.importDocuments(from: urls)
                case .failure(let error): model.statusLine = error.localizedDescription
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 30))
                    .foregroundColor(.accentColor)
            }
            VStack(spacing: 6) {
                Text("No Files Yet")
                    .font(.title3.bold())
                Text("Import text, PDF, Markdown, or code files to include as context in your chats.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                showFilePicker = true
            } label: {
                Label("Import Files", systemImage: "plus")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

struct DocumentRow: View {
    @EnvironmentObject var model: AppModel
    let doc: ImportedDocument
    var isSelected: Bool { model.settings.selectedDocumentIDs.contains(doc.id) }

    var iconName: String {
        let ext = URL(fileURLWithPath: doc.localPath).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "swift", "py", "js", "ts", "go", "rs", "cpp", "c": return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown": return "doc.text.fill"
        case "json": return "curlybraces"
        case "csv": return "tablecells.fill"
        default: return "doc.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemFill))
                    .frame(width: 38, height: 38)
                Image(systemName: iconName)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.filename)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(doc.textPreview.prefix(60))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : Color(.systemFill))
                .font(.title3)
                .animation(.spring(response: 0.3), value: isSelected)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.toggleDocumentSelection(doc) }
        .padding(.vertical, 2)
    }
}
