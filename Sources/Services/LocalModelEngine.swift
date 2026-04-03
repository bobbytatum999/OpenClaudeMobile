import Foundation
import LlamaSwift

struct LocalGenerationRequest: Sendable {
    let prompt: String
    let modelURL: URL
    let maxTokens: Int
    let sampling: SamplingConfiguration
}

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

    func generate(request: LocalGenerationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                queue.async { [self] in
                    do {
                        try self._ensureModelLoaded(at: request.modelURL)
                        try self._generateUnsafe(request: request) { token in
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

    func generate(prompt: String, modelURL: URL, maxTokens: Int = 256, temperature: Float = 0.7) -> AsyncThrowingStream<String, Error> {
        generate(request: .init(prompt: prompt, modelURL: modelURL, maxTokens: maxTokens, sampling: .init(temperature: temperature)))
    }

    private func _ensureModelLoaded(at url: URL) throws {
        if loadedPath == url.path, model != nil, context != nil, vocab != nil { return }
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
        contextParams.n_ctx = 8192
        contextParams.n_batch = 512

        let contextPointer = llama_init_from_model(modelPointer, contextParams)
        guard let contextPointer else { throw EngineError.failedToCreateContext }
        context = contextPointer
        loadedPath = url.path
    }

    private func _unloadUnsafe() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil; model = nil; vocab = nil; loadedPath = nil
    }

    private func _generateUnsafe(request: LocalGenerationRequest, onToken: (String) -> Void) throws {
        guard let context, let vocab else { throw EngineError.noModelSelected }

        var tokens = try tokenize(request.prompt, vocab: vocab)
        let maxContext = max(Int(llama_n_ctx(context)) - 256, 1024)
        if tokens.count > maxContext {
            tokens = Array(tokens.suffix(maxContext))
        }

        var batch = llama_batch_init(512, 0, 1)
        defer { llama_batch_free(batch) }

        for i in 0..<tokens.count {
            llama_batch_add_to_batch(&batch, tokens[i], Int32(i), [0], i == tokens.count - 1)
        }
        guard llama_decode(context, batch) == 0 else { throw EngineError.decodeFailed }

        var nCur = Int32(tokens.count)
        let nVocab = Int(llama_vocab_n_tokens(vocab))
        var generated = ""
        var recentTokens = Array(tokens.suffix(128))

        for _ in 0..<request.maxTokens {
            guard let logitsPointer = llama_get_logits_ith(context, batch.n_tokens - 1) else {
                throw EngineError.decodeFailed
            }
            let next = sampleToken(
                logits: logitsPointer,
                nVocab: nVocab,
                sampling: request.sampling,
                recentTokens: recentTokens
            )
            if next == llama_vocab_eos(vocab) { break }

            let piece = tokenToPiece(vocab: vocab, token: next)
            generated += piece
            onToken(piece)

            if request.sampling.stopSequences.contains(where: { generated.hasSuffix($0) }) {
                break
            }

            recentTokens.append(next)
            if recentTokens.count > 256 { recentTokens.removeFirst(recentTokens.count - 256) }

            batch.n_tokens = 0
            llama_batch_add_to_batch(&batch, next, nCur, [0], true)
            nCur += 1
            guard llama_decode(context, batch) == 0 else { throw EngineError.decodeFailed }
        }
    }

    private func tokenize(_ prompt: String, vocab: OpaquePointer) throws -> [llama_token] {
        let utf8Count = prompt.utf8.count
        var promptTokens = [llama_token](repeating: 0, count: utf8Count + 32)
        let tokenCount: Int32 = prompt.withCString { cString in
            llama_tokenize(vocab, cString, Int32(utf8Count), &promptTokens, Int32(promptTokens.count), true, true)
        }
        guard tokenCount > 0 else { throw EngineError.tokenizationFailed }
        return Array(promptTokens.prefix(Int(tokenCount)))
    }

    private func sampleToken(
        logits: UnsafePointer<Float>,
        nVocab: Int,
        sampling: SamplingConfiguration,
        recentTokens: [llama_token]
    ) -> llama_token {
        if sampling.temperature <= 0 {
            return argmax(logits: logits, nVocab: nVocab)
        }

        var scored: [(id: Int, p: Float)] = []
        scored.reserveCapacity(nVocab)

        let maxLogit = (0..<nVocab).map { logits[$0] }.max() ?? 0
        for i in 0..<nVocab {
            var logit = logits[i] - maxLogit
            if recentTokens.contains(llama_token(i)) {
                logit /= max(sampling.repetitionPenalty, 1.0)
            }
            let prob = expf(logit / sampling.temperature)
            scored.append((i, prob))
        }

        let topK = max(sampling.topK, 1)
        scored.sort { $0.p > $1.p }
        if scored.count > topK { scored = Array(scored.prefix(topK)) }

        let sum = scored.reduce(Float(0)) { $0 + $1.p }
        var normalized = scored.map { ($0.id, $0.p / max(sum, .leastNonzeroMagnitude)) }

        var cumulative: Float = 0
        var nucleus: [(Int, Float)] = []
        for (id, p) in normalized {
            cumulative += p
            nucleus.append((id, p))
            if cumulative >= sampling.topP { break }
        }

        let nucleusSum = nucleus.reduce(Float(0)) { $0 + $1.1 }
        normalized = nucleus.map { ($0.0, $0.1 / max(nucleusSum, .leastNonzeroMagnitude)) }

        var r = Float.random(in: 0..<1)
        for (id, p) in normalized {
            r -= p
            if r <= 0 { return llama_token(id) }
        }
        return llama_token(normalized.last?.0 ?? scored[0].id)
    }

    private func argmax(logits: UnsafePointer<Float>, nVocab: Int) -> llama_token {
        var best: llama_token = 0
        var bestVal = logits[0]
        for i in 1..<nVocab where logits[i] > bestVal {
            bestVal = logits[i]
            best = llama_token(i)
        }
        return best
    }

    private func tokenToPiece(vocab: OpaquePointer, token: llama_token) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        guard length > 0 else { return "" }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private func llama_batch_add_to_batch(_ batch: inout llama_batch, _ token: llama_token, _ pos: Int32, _ seq_ids: [Int32], _ logits: Bool) {
    batch.token[Int(batch.n_tokens)] = token
    batch.pos[Int(batch.n_tokens)] = pos
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
    for (i, seq_id) in seq_ids.enumerated() {
        batch.seq_id[Int(batch.n_tokens)]![i] = seq_id
    }
    batch.logits[Int(batch.n_tokens)] = logits ? 1 : 0
    batch.n_tokens += 1
}
