import Foundation

struct RetrievedChunk: Sendable {
    let documentID: UUID
    let filename: String
    let chunkID: Int
    let text: String
    let score: Int

    var citation: String {
        "[\(filename)#\(chunkID)]"
    }
}

struct DocumentContextService {
    private let chunkSize = 700
    private let overlap = 120

    func retrieveTopChunks(
        query: String,
        documents: [ImportedDocument],
        topK: Int = 5
    ) -> [RetrievedChunk] {
        let queryTerms = normalizedTerms(from: query)
        guard !queryTerms.isEmpty else { return [] }

        let scored: [RetrievedChunk] = documents.flatMap { doc in
            chunk(text: doc.textPreview).enumerated().compactMap { idx, piece in
                let terms = normalizedTerms(from: piece)
                let score = queryTerms.intersection(terms).count
                guard score > 0 else { return nil }
                return RetrievedChunk(documentID: doc.id, filename: doc.filename, chunkID: idx + 1, text: piece, score: score)
            }
        }

        return scored.sorted {
            if $0.score == $1.score { return $0.chunkID < $1.chunkID }
            return $0.score > $1.score
        }
        .prefix(topK)
        .map { $0 }
    }

    private func chunk(text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var chunks: [String] = []
        let scalars = Array(text)
        var start = 0
        while start < scalars.count {
            let end = min(start + chunkSize, scalars.count)
            chunks.append(String(scalars[start..<end]))
            if end == scalars.count { break }
            start = max(0, end - overlap)
        }
        return chunks
    }

    private func normalizedTerms(from value: String) -> Set<String> {
        let cleaned = value.lowercased().replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        return Set(cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { $0.count > 2 })
    }
}
