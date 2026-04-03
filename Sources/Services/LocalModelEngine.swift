import Foundation
import LlamaSwift

final class LocalModelEngine: @unchecked Sendable {
    struct SamplingParameters: Sendable {
        let temperature: Float
        let topK: Int
        let topP: Float
        let repetitionPenalty: Float
        let stopSequences: [String]

        static let `default` = SamplingParameters(
            temperature: 0.7,
            topK: 40,
            topP: 0.9,
            repetitionPenalty: 1.1,
            stopSequences: ["<|im_end|>", "</s>"]
        )
    }

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

    func generate(prompt: String, modelURL: URL, maxTokens: Int = 256, sampling: LocalSamplingSettings) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                queue.async { [self] in
                    do {
                        let params = SamplingParameters(
                            temperature: sampling.temperature,
                            topK: sampling.topK,
                            topP: sampling.topP,
                            repetitionPenalty: sampling.repetitionPenalty,
                            stopSequences: sampling.stopSequences
                        )
                        try self._ensureModelLoaded(at: modelURL)
                        try self._generateUnsafe(prompt: prompt, maxTokens: maxTokens, sampling: params) { token in
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
        context = nil; model = nil; vocab = nil; loadedPath = nil
    }

    private func _generateUnsafe(prompt: String, maxTokens: Int, sampling: SamplingParameters, onToken: (String) -> Void) throws {
        guard let model, let context, let vocab else { throw EngineError.noModelSelected }

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
            llama_batch_add_to_batch(&batch, tokens[i], Int32(i), [0], i == tokens.count - 1)
        }
        guard llama_decode(context, batch) == 0 else { throw EngineError.decodeFailed }

        var n_cur = Int32(tokens.count)
        let n_vocab = Int(llama_vocab_n_tokens(vocab))
        var generatedTokens: [llama_token] = []
        var emittedText = ""

        for _ in 0..<maxTokens {
            let logits = llama_get_logits_ith(context, batch.n_tokens - 1)!
            let next = sampleNextToken(
                logits: logits,
                vocabSize: n_vocab,
                generatedTokens: generatedTokens,
                sampling: sampling
            )

            if next == llama_vocab_eos(vocab) { break }

            let piece = tokenToPiece(vocab: vocab, token: next)
            emittedText += piece
            if sampling.stopSequences.contains(where: { emittedText.hasSuffix($0) }) { break }
            onToken(piece)
            generatedTokens.append(next)

            batch.n_tokens = 0
            llama_batch_add_to_batch(&batch, next, n_cur, [0], true)
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

    private func sampleNextToken(
        logits: UnsafePointer<Float>,
        vocabSize: Int,
        generatedTokens: [llama_token],
        sampling: SamplingParameters
    ) -> llama_token {
        var adjusted = (0..<vocabSize).map { logits[$0] }

        if sampling.repetitionPenalty > 1.0 {
            let recent = Set(generatedTokens.suffix(128).map(Int.init))
            for idx in recent where idx < adjusted.count {
                adjusted[idx] /= sampling.repetitionPenalty
            }
        }

        let temperature = max(0.0001, sampling.temperature)
        adjusted = adjusted.map { $0 / temperature }

        let topK = min(max(1, sampling.topK), vocabSize)
        let candidates = (0..<vocabSize).sorted { adjusted[$0] > adjusted[$1] }.prefix(topK)
        let maxVal = candidates.map { adjusted[$0] }.max() ?? 0

        var probs: [(Int, Float)] = candidates.map { idx in
            (idx, expf(adjusted[idx] - maxVal))
        }
        let total = probs.reduce(Float(0)) { $0 + $1.1 }
        guard total > 0 else { return llama_token(candidates.first ?? 0) }
        probs = probs.map { ($0.0, $0.1 / total) }.sorted { $0.1 > $1.1 }

        var cumulative: Float = 0
        let nucleus = probs.prefix { pair in
            cumulative += pair.1
            return cumulative <= sampling.topP || cumulative == pair.1
        }
        let bucket = Array(nucleus.isEmpty ? probs : nucleus)

        let r = Float.random(in: 0..<1)
        var running: Float = 0
        for (idx, p) in bucket {
            running += p
            if r <= running { return llama_token(idx) }
        }
        return llama_token(bucket.last?.0 ?? 0)
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
