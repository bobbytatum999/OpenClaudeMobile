import Foundation
import LlamaSwift

final class LocalModelEngine: @unchecked Sendable {
    enum EngineError: LocalizedError {
        case noModelSelected
        case failedToLoadModel
        case failedToCreateContext
        case tokenizationFailed
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .noModelSelected: return "No local model is selected."
            case .failedToLoadModel: return "The GGUF model could not be loaded."
            case .failedToCreateContext: return "The local inference context could not be created."
            case .tokenizationFailed: return "The prompt could not be tokenized."
            case .decodeFailed: return "The local model failed during decoding."
            }
        }
    }

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var loadedPath: String?
    private var backendInitialized = false
    private let queue = DispatchQueue(label: "OpenClaudeMobile.LocalModelEngine")

    func unload() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                self._unloadUnsafe()
                continuation.resume()
            }
        }
    }

    func generate(prompt: String, modelURL: URL, maxTokens: Int = 256) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            queue.async { [self] in
                do {
                    try self._ensureModelLoaded(at: modelURL)
                    try self._generateUnsafe(prompt: prompt, maxTokens: maxTokens) { token in
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func _ensureModelLoaded(at url: URL) throws {
        if loadedPath == url.path, model != nil, context != nil, vocab != nil {
            return
        }
        _unloadUnsafe()
        if !backendInitialized {
            llama_backend_init()
            backendInitialized = true
        }

        let modelParams = llama_model_default_params()
        let modelPointer: OpaquePointer? = url.path.withCString { cString in
            llama_model_load_from_file(cString, modelParams)
        }
        guard let modelPointer else { throw EngineError.failedToLoadModel }
        model = modelPointer
        vocab = llama_model_get_vocab(modelPointer)

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 4096
        contextParams.n_batch = 512
        let contextPointer = llama_init_from_model(modelPointer, contextParams)
        guard let contextPointer else { throw EngineError.failedToCreateContext }
        context = contextPointer
        loadedPath = url.path
    }

    private func _unloadUnsafe() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        vocab = nil
        loadedPath = nil
    }

    private func _generateUnsafe(prompt: String, maxTokens: Int, onToken: (String) -> Void) throws {
        guard model != nil, let context, let vocab else { throw EngineError.noModelSelected }

        let utf8Count = prompt.utf8.count
        var promptTokens = [llama_token](repeating: 0, count: max(utf8Count + 16, 64))
        let tokenCount: Int32 = prompt.withCString { cString in
            llama_tokenize(
                vocab,
                cString,
                Int32(utf8Count),
                &promptTokens,
                Int32(promptTokens.count),
                true,
                true
            )
        }
        guard tokenCount > 0 else { throw EngineError.tokenizationFailed }
        let tokens = Array(promptTokens.prefix(Int(tokenCount)))

        var batch = llama_batch_init(512, 0, 1)
        defer { llama_batch_free(batch) }

        batch.n_tokens = Int32(tokens.count)
        for i in 0..<tokens.count {
            batch.token[i] = tokens[i]
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            if let seqIDs = batch.seq_id, let seq = seqIDs[i] {
                seq[0] = 0
            }
            batch.logits[i] = 0
        }
        if batch.n_tokens > 0 {
            batch.logits[Int(batch.n_tokens) - 1] = 1
        }

        guard llama_decode(context, batch) == 0 else {
            throw EngineError.decodeFailed
        }

        var currentPosition = batch.n_tokens
        let eos = llama_vocab_eos(vocab)

        for _ in 0..<maxTokens {
            guard let logits = llama_get_logits_ith(context, batch.n_tokens - 1) else {
                throw EngineError.decodeFailed
            }
            let vocabSize = Int(llama_vocab_n_tokens(vocab))
            var nextToken: llama_token = 0
            var bestLogit = logits[0]
            if vocabSize > 1 {
                for i in 1..<vocabSize {
                    if logits[i] > bestLogit {
                        bestLogit = logits[i]
                        nextToken = llama_token(i)
                    }
                }
            }
            if nextToken == eos { break }
            let piece = tokenToPiece(vocab: vocab, token: nextToken)
            onToken(piece)

            batch.n_tokens = 1
            batch.token[0] = nextToken
            batch.pos[0] = currentPosition
            batch.n_seq_id[0] = 1
            if let seqIDs = batch.seq_id, let seq = seqIDs[0] {
                seq[0] = 0
            }
            batch.logits[0] = 1
            currentPosition += 1

            guard llama_decode(context, batch) == 0 else {
                throw EngineError.decodeFailed
            }
        }
    }

    private func tokenToPiece(vocab: OpaquePointer, token: llama_token) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        guard length > 0 else { return "" }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
