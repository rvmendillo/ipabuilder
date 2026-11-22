import Foundation
import ReyForgeCore
import llama

/// On-device LLM inference with llama.cpp (Metal on iPhone, CPU elsewhere).
///
/// Uses only long-stable llama.cpp C APIs (vocab/sampler-chain/memory/state) and avoids
/// functions whose signatures change between releases, so it builds against a range of
/// llama.xcframework versions.
public final class LlamaEngine: LLMEngine {
    public let id = "llama"
    public let displayName: String
    public let tier: EngineTier = .local
    public let supportsGrammar = true
    public let modelURL: URL

    public var contextLength: UInt32 = 4096
    public var gpuLayers: Int32 = 99
    public var threads: Int32 = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 1)))
    /// Stop when the model repeats the same line (small models can loop).
    public var stopOnRepeatedLines = true

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var chatML = true
    private var thinkTemplate = false
    private var rawTemplate: String?
    private let queue = DispatchQueue(label: "com.reyforge.llama", qos: .userInitiated)
    private let cancelLock = NSLock()
    private var _cancelled = false
    private var cancelled: Bool {
        get { cancelLock.lock(); defer { cancelLock.unlock() }; return _cancelled }
        set { cancelLock.lock(); _cancelled = newValue; cancelLock.unlock() }
    }
    // Prefix (system prompt) state snapshot so repeated requests skip re-processing it.
    private var prefixKey: Int?
    private var prefixState: [UInt8] = []

    public private(set) var lastStats = Stats()
    public struct Stats { public var promptTokens = 0; public var generatedTokens = 0; public var promptSeconds = 0.0; public var generateSeconds = 0.0; public var reusedPrefix = false
        public var tokensPerSecond: Double { generateSeconds > 0 ? Double(generatedTokens) / generateSeconds : 0 }
    }

    private static let backendOnce: Void = {
        llama_log_set({ level, text, _ in
            // Only surface errors; llama.cpp is very chatty.
            if level == GGML_LOG_LEVEL_ERROR, let text = text { fputs(String(cString: text), stderr) }
        }, nil)
        llama_backend_init()
    }()

    public init(modelURL: URL, displayName: String? = nil) {
        self.modelURL = modelURL
        self.displayName = displayName ?? modelURL.deletingPathExtension().lastPathComponent
        #if targetEnvironment(simulator)
        gpuLayers = 0
        #endif
    }

    deinit { unload() }

    public var isLoaded: Bool { model != nil && context != nil }

    /// Loads the model (idempotent). Call off the main thread or let `generate` do it.
    public func load() throws {
        _ = LlamaEngine.backendOnce
        if isLoaded { return }
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw EngineError("Model file not found: \(modelURL.lastPathComponent)") }
        var mp = llama_model_default_params()
        mp.n_gpu_layers = gpuLayers
        guard let m = llama_model_load_from_file(modelURL.path, mp) else { throw EngineError("Could not load \(modelURL.lastPathComponent). The file may be incomplete.") }
        var cp = llama_context_default_params()
        cp.n_ctx = contextLength
        cp.n_batch = 512
        cp.n_ubatch = 512
        cp.n_threads = threads
        cp.n_threads_batch = threads
        guard let c = llama_init_from_model(m, cp) else {
            llama_model_free(m)
            throw EngineError("Not enough memory to start the model. Try a smaller model in AI Settings.")
        }
        model = m
        context = c
        vocab = llama_model_get_vocab(m)
        if let t = llama_model_chat_template(m, nil) {
            let s = String(cString: t)
            rawTemplate = s
            chatML = s.contains("<|im_start|>")
            thinkTemplate = s.contains("<think>")
        }
        prefixKey = nil
        prefixState = []
    }

    public func unload() {
        if let c = context { llama_free(c) }
        if let m = model { llama_model_free(m) }
        context = nil; model = nil; vocab = nil
        prefixKey = nil; prefixState = []
    }

    public func cancel() { cancelled = true }

    // MARK: Prompt formatting

    func formatPrefix(system: String) -> String {
        if chatML { return "<|im_start|>system\n\(system)<|im_end|>\n" }
        return applyTemplate([("system", system)], addAssistant: false) ?? "System: \(system)\n\n"
    }

    func formatTurns(_ messages: [LLMMessage]) -> String {
        if chatML {
            var s = ""
            for m in messages {
                let role = m.role == "assistant" ? "assistant" : "user"
                s += "<|im_start|>\(role)\n\(m.content)<|im_end|>\n"
            }
            s += "<|im_start|>assistant\n"
            if thinkTemplate { s += "<think>\n\n</think>\n\n" }
            return s
        }
        return applyTemplate(messages.map { ($0.role, $0.content) }, addAssistant: true) ?? (messages.map { "\($0.role.capitalized): \($0.content)" }.joined(separator: "\n") + "\nAssistant: ")
    }

    /// Falls back to llama.cpp's built-in template support for non-ChatML models.
    func applyTemplate(_ messages: [(String, String)], addAssistant: Bool) -> String? {
        guard let template = rawTemplate else { return nil }
        var cStrings: [(UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)] = messages.map { (strdup($0.0)!, strdup($0.1)!) }
        defer { for (r, c) in cStrings { free(r); free(c) } }
        var chat = cStrings.map { llama_chat_message(role: UnsafePointer($0.0), content: UnsafePointer($0.1)) }
        var buf = [CChar](repeating: 0, count: 8192)
        var n = llama_chat_apply_template(template, &chat, chat.count, addAssistant, &buf, Int32(buf.count))
        if n > Int32(buf.count) {
            buf = [CChar](repeating: 0, count: Int(n) + 1)
            n = llama_chat_apply_template(template, &chat, chat.count, addAssistant, &buf, Int32(buf.count))
        }
        cStrings.removeAll(keepingCapacity: false)
        guard n > 0 else { return nil }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: Tokens

    func tokenize(_ text: String) throws -> [llama_token] {
        guard let vocab = vocab else { throw EngineError("Model not loaded") }
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 16)
        var n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), false, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n) + 16)
            n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), false, true)
        }
        guard n >= 0 else { throw EngineError("Tokenization failed") }
        return Array(tokens.prefix(Int(n)))
    }

    func piece(_ token: llama_token) -> [UInt8] {
        guard let vocab = vocab else { return [] }
        var buf = [CChar](repeating: 0, count: 64)
        var n = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
        if n < 0 {
            buf = [CChar](repeating: 0, count: Int(-n) + 8)
            n = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
        }
        return n > 0 ? buf.prefix(Int(n)).map { UInt8(bitPattern: $0) } : []
    }

    func decode(_ tokens: [llama_token]) throws {
        guard let ctx = context else { throw EngineError("Model not loaded") }
        var start = 0
        while start < tokens.count {
            if cancelled { throw CancellationError() }
            let end = min(tokens.count, start + 512)
            var slice = Array(tokens[start..<end])
            let rc = slice.withUnsafeMutableBufferPointer { ptr -> Int32 in
                llama_decode(ctx, llama_batch_get_one(ptr.baseAddress, Int32(ptr.count)))
            }
            if rc != 0 { throw EngineError(rc == 1 ? "The conversation is too long for the model's context." : "Model decode failed (\(rc)).") }
            start = end
        }
    }

    /// Restores (or builds and snapshots) the system-prompt state for sequence 0.
    func preparePrefix(_ prefixTokens: [llama_token], key: Int) throws -> Bool {
        guard let ctx = context else { throw EngineError("Model not loaded") }
        let mem = llama_get_memory(ctx)
        llama_memory_clear(mem, true)
        if prefixKey == key, !prefixState.isEmpty {
            let restored = prefixState.withUnsafeBufferPointer { llama_state_seq_set_data(ctx, $0.baseAddress, $0.count, 0) }
            if restored > 0 { return true }
            llama_memory_clear(mem, true)
        }
        try decode(prefixTokens)
        let size = llama_state_seq_get_size(ctx, 0)
        if size > 0 && size < 400_000_000 {
            var buf = [UInt8](repeating: 0, count: size)
            let written = buf.withUnsafeMutableBufferPointer { llama_state_seq_get_data(ctx, $0.baseAddress, size, 0) }
            if written > 0 { prefixState = Array(buf.prefix(written)); prefixKey = key } else { prefixKey = nil; prefixState = [] }
        }
        return false
    }

    // MARK: Generation

    public func generate(_ request: LLMRequest, stream: LLMStream) async throws -> String {
        cancelled = false
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async {
                do { cont.resume(returning: try self.run(request, stream: stream)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func run(_ request: LLMRequest, stream: LLMStream) throws -> String {
        try load()
        guard let ctx = context, let vocab = vocab else { throw EngineError("Model not loaded") }
        var stats = Stats()
        let t0 = Date()
        let prefixTokens = try tokenize(formatPrefix(system: request.system))
        let turnTokens = try tokenize(formatTurns(request.messages))
        guard prefixTokens.count + turnTokens.count + 16 < Int(llama_n_ctx(ctx)) else { throw EngineError("The request is too long for this model.") }
        stats.reusedPrefix = try preparePrefix(prefixTokens, key: request.system.hashValue)
        try decode(turnTokens)
        stats.promptTokens = prefixTokens.count + turnTokens.count
        stats.promptSeconds = Date().timeIntervalSince(t0)

        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(chain) }
        if let g = request.grammar, !g.isEmpty {
            guard let gs = llama_sampler_init_grammar(vocab, g, "root") else { throw EngineError("Invalid grammar") }
            llama_sampler_chain_add(chain, gs)
        }
        if request.temperature <= 0.01 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(request.temperature)))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))
        }

        let t1 = Date()
        var output = ""
        var pending: [UInt8] = []
        var currentLine = ""
        var seenLines = Set<String>()
        let budget = max(1, min(request.maxTokens, Int(llama_n_ctx(ctx)) - stats.promptTokens - 4))
        generation: for _ in 0..<budget {
            if cancelled { break }
            let token = llama_sampler_sample(chain, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            pending += piece(token)
            // Emit only complete UTF-8 sequences.
            let (text, rest) = LlamaEngine.splitValidUTF8(pending)
            pending = rest
            if !text.isEmpty {
                output += text
                stream.onText(text)
                for ch in text {
                    if ch == "\n" {
                        let line = currentLine.trimmingCharacters(in: .whitespaces)
                        if stopOnRepeatedLines, line.count > 6, !line.hasPrefix("DIVIDER"), !line.hasPrefix("SPACER"), seenLines.contains(line) {
                            // Drop the repeated line and stop.
                            if let r = output.range(of: currentLine + "\n", options: .backwards) { output.removeSubrange(r) }
                            break generation
                        }
                        if !line.isEmpty { seenLines.insert(line) }
                        currentLine = ""
                    } else { currentLine.append(ch) }
                }
                if request.stopSequences.contains(where: { output.hasSuffix($0) || currentLine.trimmingCharacters(in: .whitespaces) == $0 }) { break }
            }
            stats.generatedTokens += 1
            var t = token
            let rc = llama_decode(ctx, llama_batch_get_one(&t, 1))
            if rc != 0 { break }
        }
        stats.generateSeconds = Date().timeIntervalSince(t1)
        lastStats = stats
        if cancelled { throw CancellationError() }
        return output
    }

    /// Splits bytes into the longest valid UTF-8 prefix and an incomplete tail.
    static func splitValidUTF8(_ bytes: [UInt8]) -> (String, [UInt8]) {
        if let s = String(bytes: bytes, encoding: .utf8) { return (s, []) }
        for cut in stride(from: bytes.count - 1, through: max(0, bytes.count - 4), by: -1) {
            if let s = String(bytes: bytes[..<cut], encoding: .utf8) { return (s, Array(bytes[cut...])) }
        }
        // Not recoverable: replace invalid bytes.
        return (String(decoding: bytes, as: UTF8.self), [])
    }
}
