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
            let task = Task {
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
            continuation.onTermination = { _ in task.cancel() }
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

        var modelParams = llama_model_default_params()
        modelParams.use_mmap = true
        modelParams.use_mlock = true
        
        let modelPointer: OpaquePointer? = url.path.withCString { cString in
            llama_model_load_from_file(cString, modelParams)
        }
        guard let modelPointer else { throw EngineError.failedToLoadModel }
        model = modelPointer
        vocab = llama_model_get_vocab(modelPointer)

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 4096
        contextParams.n_batch = 512
        contextParams.type_k = GGML_TYPE_F16
        contextParams.type_v = GGML_TYPE_F16
        
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
        guard let model, let context, let vocab else { throw EngineError.noModelSelected }

        llama_kv_cache_clear(context)

        let utf8Count = prompt.utf8.count
        var promptTokens = [llama_token](repeating: 0, count: utf8Count + 16)
        let tokenCount: Int32 = prompt.withCString { cString in
            llama_tokenize(vocab, cString, Int32(utf8Count), &promptTokens, Int32(promptTokens.count), true, true)
        }
        guard tokenCount > 0 else { throw EngineError.tokenizationFailed }
        let tokens = Array(promptTokens.prefix(Int(tokenCount)))

        var batch = llama_batch_init(512, 0, 1)
        defer { llama_batch_free(batch) }

        for i in 0..<tokens.count {
            llama_batch_add(&batch, tokens[i], Int32(i), [0], i == tokens.count - 1)
        }

        guard llama_decode(context, batch) == 0 else { throw EngineError.decodeFailed }

        var n_cur = Int32(tokens.count)
        var lastToken = tokens.last!

        for _ in 0..<maxTokens {
            let n_vocab = llama_vocab_n_tokens(vocab)
            let logits = llama_get_logits_ith(context, batch.n_tokens - 1)!
            
            var candidates = [llama_token_data](repeating: llama_token_data(), count: Int(n_vocab))
            for i in 0..<Int(n_vocab) {
                candidates[i] = llama_token_data(id: llama_token(i), logit: logits[i], p: 0.0)
            }
            
            var candidatesList = llama_token_data_array(data: &candidates, size: candidates.count, sorted: false)
            let id = llama_sample_token_greedy(context, &candidatesList)
            
            if id == llama_vocab_eos(vocab) { break }
            
            let piece = tokenToPiece(vocab: vocab, token: id)
            onToken(piece)

            llama_batch_clear(&batch)
            llama_batch_add(&batch, id, n_cur, [0], true)
            
            n_cur += 1
            guard llama_decode(context, batch) == 0 else { throw EngineError.decodeFailed }
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

private func llama_batch_add(_ batch: inout llama_batch, _ token: llama_token, _ pos: Int32, _ seq_ids: [Int32], _ logits: Bool) {
    batch.token[Int(batch.n_tokens)] = token
    batch.pos[Int(batch.n_tokens)] = pos
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
    for (i, seq_id) in seq_ids.enumerated() {
        batch.seq_id[Int(batch.n_tokens)]![i] = seq_id
    }
    batch.logits[Int(batch.n_tokens)] = logits ? 1 : 0
    batch.n_tokens += 1
}

private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}
