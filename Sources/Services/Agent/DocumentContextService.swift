import Foundation

struct DocumentContextService {
    func topChunks(from documents: [ImportedDocument], query: String, limit: Int = 6, chunkSize: Int = 550) -> [DocumentChunk] {
        let queryTerms = Set(tokenize(query))
        var chunks: [DocumentChunk] = []

        for doc in documents {
            let pieces = chunk(text: doc.textPreview, chunkSize: chunkSize)
            for piece in pieces where !piece.isEmpty {
                let terms = tokenize(piece)
                let overlap = terms.filter { queryTerms.contains($0) }.count
                let score = Double(overlap) / Double(max(queryTerms.count, 1))
                chunks.append(DocumentChunk(documentID: doc.id, filename: doc.filename, text: piece, score: score))
            }
        }

        return chunks
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.text.count > rhs.text.count }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    private func chunk(text: String, chunkSize: Int) -> [String] {
        guard text.count > chunkSize else { return [text] }
        var result: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n\n") {
            if current.count + paragraph.count > chunkSize, !current.isEmpty {
                result.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + paragraph
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }
}
