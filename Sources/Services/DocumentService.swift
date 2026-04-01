import Foundation
import PDFKit
import UniformTypeIdentifiers

struct DocumentService {
    enum DocumentError: LocalizedError {
        case unsupported

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "This file type cannot be previewed as text."
            }
        }
    }

    func importDocument(from sourceURL: URL) throws -> ImportedDocument {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let destination = AppPersistence.importedFilesDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let preview = try textPreview(for: destination)
        let contentType = UTType(filenameExtension: destination.pathExtension)?.identifier ?? "application/octet-stream"
        return ImportedDocument(filename: destination.lastPathComponent, localPath: destination.path, contentType: contentType, textPreview: preview)
    }

    func textPreview(for fileURL: URL) throws -> String {
        let ext = fileURL.pathExtension.lowercased()
        if ["txt", "md", "json", "swift", "py", "js", "ts", "tsx", "yml", "yaml", "xml", "html", "css", "c", "cpp", "h", "m", "mm", "java", "kt", "rs", "go", "rb", "sh"].contains(ext) {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            return String(text.prefix(16_000))
        }
        if ext == "pdf", let pdf = PDFDocument(url: fileURL) {
            let pages = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }
            return String(pages.joined(separator: "\n\n").prefix(16_000))
        }
        throw DocumentError.unsupported
    }
}
