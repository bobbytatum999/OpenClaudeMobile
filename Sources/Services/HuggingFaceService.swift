import Foundation

struct HuggingFaceService {
    enum ServiceError: LocalizedError {
        case invalidResponse
        case missingGGUF

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The Hugging Face response could not be decoded."
            case .missingGGUF:
                return "No GGUF file was found for this repository."
            }
        }
    }

    private struct SearchResponseItem: Decodable {
        let id: String
        let downloads: Int?
        let likes: Int?
        let pipelineTag: String?
        let `private`: Bool?
        let lastModified: Date?
        let siblings: [Sibling]?

        struct Sibling: Decodable {
            let rfilename: String
            let size: Int64?
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchModels(query: String, token: String) async throws -> [HuggingFaceModelSummary] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            .init(name: "search", value: query),
            .init(name: "limit", value: "25"),
            .init(name: "full", value: "true")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 60
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = try decoder.decode([SearchResponseItem].self, from: data)
        return items.map {
            HuggingFaceModelSummary(
                id: $0.id,
                downloads: $0.downloads,
                likes: $0.likes,
                pipelineTag: $0.pipelineTag,
                privateRepo: $0.private ?? false,
                lastModified: $0.lastModified,
                siblings: ($0.siblings ?? []).map { HuggingFaceSibling(rfilename: $0.rfilename, size: $0.size) }
            )
        }
    }

    func resolveDownloadURL(repoID: String, filePath: String) -> URL {
        let escaped = filePath.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        return URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(escaped)?download=true")!
    }

    private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        var onProgress: ((Double) -> Void)?
        var onCompletion: ((Result<URL, Error>) -> Void)?
        private var temporaryDestination: URL?

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            try? FileManager.default.moveItem(at: location, to: tempDir)
            temporaryDestination = tempDir
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                onCompletion?(.failure(error))
            } else if let temp = temporaryDestination {
                if let response = task.response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
                    onCompletion?(.failure(ServiceError.invalidResponse))
                } else {
                    onCompletion?(.success(temp))
                }
            } else {
                onCompletion?(.failure(ServiceError.missingGGUF))
            }
        }
    }

    func downloadGGUF(repoID: String, sibling: HuggingFaceSibling, token: String, onProgress: @escaping (Double) -> Void) async throws -> InstalledModel {
        let destinationDirectory = AppPersistence.modelsDirectory.appendingPathComponent(repoID.replacingOccurrences(of: "/", with: "__"), isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = destinationDirectory.appendingPathComponent(sibling.filename)

        var request = URLRequest(url: resolveDownloadURL(repoID: repoID, filePath: sibling.rfilename))
        request.timeoutInterval = 60 * 60 * 12
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let delegate = DownloadDelegate()
        delegate.onProgress = onProgress
        let tempSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let temporaryURL: URL = try await withCheckedThrowingContinuation { continuation in
            var isResumed = false
            delegate.onCompletion = { result in
                guard !isResumed else { return }
                isResumed = true
                continuation.resume(with: result)
            }
            let task = tempSession.downloadTask(with: request)
            task.resume()
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        let values = try destination.resourceValues(forKeys: [.fileSizeKey])
        return InstalledModel(
            id: "\(repoID)::\(sibling.rfilename)",
            repoID: repoID,
            filename: sibling.filename,
            localPath: destination.path,
            sizeBytes: Int64(values.fileSize ?? 0),
            installedAt: .now
        )
    }
}
