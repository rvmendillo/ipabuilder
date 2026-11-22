import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum EngineTier: String, Codable, Hashable {
    /// Small on-device models: the design engine supplies structure, the model supplies content.
    case local
    /// Capable models (Claude, Apple Intelligence, large OpenAI-compatible models): they write full scripts.
    case strong
}

public struct LLMMessage: Hashable, Codable {
    public var role: String
    public var content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct LLMRequest {
    public var system: String
    public var messages: [LLMMessage]
    public var grammar: String?
    public var maxTokens: Int
    public var temperature: Double
    public var stopSequences: [String]
    public init(system: String, messages: [LLMMessage], grammar: String? = nil, maxTokens: Int = 600, temperature: Double = 0.2, stopSequences: [String] = []) {
        self.system = system; self.messages = messages; self.grammar = grammar; self.maxTokens = maxTokens
        self.temperature = temperature; self.stopSequences = stopSequences
    }
}

/// Streaming callbacks: visible text and (for reasoning models) a thinking summary.
public struct LLMStream {
    public var onText: (String) -> Void
    public var onThinking: (String) -> Void
    public init(onText: @escaping (String) -> Void = { _ in }, onThinking: @escaping (String) -> Void = { _ in }) {
        self.onText = onText; self.onThinking = onThinking
    }
}

public protocol LLMEngine: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var tier: EngineTier { get }
    var supportsGrammar: Bool { get }
    func generate(_ request: LLMRequest, stream: LLMStream) async throws -> String
    func cancel()
}

public struct EngineError: LocalizedError, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
    public var errorDescription: String? { message }
}

// MARK: - Server-sent events

public struct SSEParser {
    var buffer = ""
    var event: String?
    var data: [String] = []
    public init() {}

    /// Feeds raw text; returns complete (event, data) pairs.
    public mutating func feed(_ chunk: String) -> [(event: String?, data: String)] {
        buffer += chunk
        var out: [(String?, String)] = []
        while let nl = buffer.firstIndex(of: "\n") {
            var line = String(buffer[..<nl])
            buffer = String(buffer[buffer.index(after: nl)...])
            if line.hasSuffix("\r") { line.removeLast() }
            if line.isEmpty {
                if !data.isEmpty { out.append((event, data.joined(separator: "\n"))) }
                event = nil; data = []
            } else if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                data.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        return out.map { (event: $0.0, data: $0.1) }
    }

    public mutating func finish() -> [(event: String?, data: String)] {
        var out = feed("\n\n")
        if !data.isEmpty { out.append((event: event, data: data.joined(separator: "\n"))); data = [] }
        return out
    }
}

/// Streams lines from a URLRequest (async bytes on Apple platforms, buffered elsewhere).
enum HTTPStreamer {
    static func stream(_ request: URLRequest, session: URLSession, onChunk: (String) -> Void) async throws -> (Int, String) {
        #if canImport(Darwin)
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if !(200..<300).contains(status) {
            var body = ""
            for try await line in bytes.lines { body += line + "\n"; if body.count > 8000 { break } }
            return (status, body)
        }
        // `lines` drops the blank lines that delimit SSE events, so each data line is
        // terminated as its own event (both APIs carry the event type inside the JSON).
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("data:") { onChunk(line + "\n\n") }
        }
        return (status, "")
        #else
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        let text = String(data: data, encoding: .utf8) ?? ""
        if (200..<300).contains(status) { onChunk(text + "\n\n") }
        return (status, (200..<300).contains(status) ? "" : text)
        #endif
    }
}

// MARK: - Claude (Anthropic Messages API, user's own key)

public final class ClaudeEngine: LLMEngine {
    public static let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
    public let id = "claude"
    public var displayName: String { "Claude (\(model))" }
    public let tier: EngineTier = .strong
    public let supportsGrammar = false
    public var apiKey: String
    public var model: String
    /// "low" | "medium" | "high" — Claude Opus 5.5 defaults to medium; set explicitly.
    public var effort: String
    public var baseURL: URL
    let session: URLSession
    private var task: Task<String, Error>?

    public init(apiKey: String, model: String = "claude-opus-5-5", effort: String = "medium",
                baseURL: URL = URL(string: "https://api.anthropic.com")!, session: URLSession = .shared) {
        self.apiKey = apiKey; self.model = model; self.effort = effort; self.baseURL = baseURL; self.session = session
    }

    /// Builds the Messages API request body.
    public func body(for request: LLMRequest) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 64000,
            "stream": true,
            "system": request.system,
            "messages": request.messages.map { ["role": $0.role == "assistant" ? "assistant" : "user", "content": $0.content] },
            // Adaptive thinking is always on for current models; show a readable summary in the chat.
            "thinking": ["type": "adaptive", "display": "summarized"],
            "output_config": ["effort": effort],
        ]
        if supportsServerFallback { body["fallbacks"] = "default" }
        return body
    }

    /// Server-side refusal fallback is available on Opus/Sonnet 5.5 (not Haiku).
    var supportsServerFallback: Bool { !model.contains("haiku") }

    public func urlRequest(for request: LLMRequest) throws -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        r.httpMethod = "POST"
        r.timeoutInterval = 300
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        r.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if supportsServerFallback { r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
        r.httpBody = try JSONSerialization.data(withJSONObject: body(for: request))
        return r
    }

    public func generate(_ request: LLMRequest, stream: LLMStream) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { throw EngineError("Add your Anthropic API key in AI Settings to use Claude.") }
        let urlRequest = try self.urlRequest(for: request)
        let session = self.session
        let t = Task<String, Error> {
            var parser = SSEParser()
            var text = ""
            var stopReason: String?
            var streamError: String?
            func handle(_ events: [(event: String?, data: String)]) {
                for e in events {
                    guard let d = e.data.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
                    let type = obj["type"] as? String ?? e.event ?? ""
                    switch type {
                    case "content_block_delta":
                        let delta = obj["delta"] as? [String: Any] ?? [:]
                        if let t = delta["text"] as? String { text += t; stream.onText(t) }
                        if let th = delta["thinking"] as? String { stream.onThinking(th) }
                    case "message_delta":
                        if let delta = obj["delta"] as? [String: Any], let s = delta["stop_reason"] as? String { stopReason = s }
                    case "error":
                        let err = obj["error"] as? [String: Any]
                        streamError = err?["message"] as? String ?? "Claude returned an error."
                    default: break
                    }
                }
            }
            let (status, errorBody) = try await HTTPStreamer.stream(urlRequest, session: session) { chunk in handle(parser.feed(chunk)) }
            handle(parser.finish())
            if !(200..<300).contains(status) {
                let msg = (try? JSONSerialization.jsonObject(with: Data(errorBody.utf8)) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                throw EngineError("Claude API error \(status): \(msg ?? errorBody.prefix(200).description)")
            }
            if let e = streamError { throw EngineError(e) }
            if stopReason == "refusal" && text.isEmpty { throw EngineError("Claude declined this request. Try rephrasing it.") }
            return text
        }
        task = t
        return try await t.value
    }

    public func cancel() { task?.cancel() }
}

// MARK: - OpenAI-compatible (Ollama, LM Studio, OpenRouter, any /v1/chat/completions server)

public final class OpenAICompatibleEngine: LLMEngine {
    public let id = "openai-compatible"
    public var displayName: String { "\(model) @ \(baseURL.host ?? "server")" }
    public var tier: EngineTier
    public let supportsGrammar = false
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    let session: URLSession
    private var task: Task<String, Error>?

    public init(baseURL: URL, apiKey: String = "", model: String, tier: EngineTier = .strong, session: URLSession = .shared) {
        self.baseURL = baseURL; self.apiKey = apiKey; self.model = model; self.tier = tier; self.session = session
    }

    public func urlRequest(for request: LLMRequest) throws -> URLRequest {
        var url = baseURL
        if !url.path.hasSuffix("/chat/completions") {
            if !url.path.hasSuffix("/v1") && !url.path.contains("/v1/") { url = url.appendingPathComponent("v1") }
            url = url.appendingPathComponent("chat/completions")
        }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 300
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        var messages: [[String: String]] = [["role": "system", "content": request.system]]
        messages += request.messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = ["model": model, "messages": messages, "stream": true, "temperature": request.temperature, "max_tokens": max(request.maxTokens, 1024)]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    public func generate(_ request: LLMRequest, stream: LLMStream) async throws -> String {
        let urlRequest = try self.urlRequest(for: request)
        let session = self.session
        let t = Task<String, Error> {
            var parser = SSEParser()
            var text = ""
            func handle(_ events: [(event: String?, data: String)]) {
                for e in events where e.data != "[DONE]" {
                    guard let d = e.data.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
                    if let choices = obj["choices"] as? [[String: Any]], let first = choices.first {
                        if let delta = first["delta"] as? [String: Any] {
                            if let c = delta["content"] as? String { text += c; stream.onText(c) }
                            if let r = delta["reasoning_content"] as? String ?? delta["reasoning"] as? String { stream.onThinking(r) }
                        } else if let msg = first["message"] as? [String: Any], let c = msg["content"] as? String {
                            text += c; stream.onText(c)
                        }
                    }
                }
            }
            let (status, errorBody) = try await HTTPStreamer.stream(urlRequest, session: session) { chunk in handle(parser.feed(chunk)) }
            handle(parser.finish())
            if !(200..<300).contains(status) { throw EngineError("Server error \(status): \(errorBody.prefix(240))") }
            return text
        }
        task = t
        return try await t.value
    }

    public func cancel() { task?.cancel() }
}

/// A scripted engine for tests and demos.
public final class ScriptedEngine: LLMEngine {
    public let id = "scripted"
    public var displayName = "Scripted"
    public var tier: EngineTier
    public let supportsGrammar = true
    public var responses: [String]
    public private(set) var requests: [LLMRequest] = []
    public init(tier: EngineTier = .local, responses: [String]) { self.tier = tier; self.responses = responses }
    public func generate(_ request: LLMRequest, stream: LLMStream) async throws -> String {
        requests.append(request)
        let r = responses.isEmpty ? "" : responses.removeFirst()
        for word in r.split(separator: " ", omittingEmptySubsequences: false) { stream.onText(String(word) + " ") }
        return r
    }
    public func cancel() {}
}
