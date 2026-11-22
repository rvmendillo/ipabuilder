import Foundation
import SwiftUI
import ReyForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which brain powers ReyForge AI.
enum AIEngineKind: String, CaseIterable, Identifiable {
    case builtin, apple, claude, openai, offline
    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtin: return "Built-in model"
        case .apple: return "Apple Intelligence"
        case .claude: return "Claude"
        case .openai: return "OpenAI-compatible server"
        case .offline: return "Design engine only"
        }
    }

    var symbol: String {
        switch self {
        case .builtin: return "cpu"
        case .apple: return "apple.intelligence"
        case .claude: return "sparkle"
        case .openai: return "server.rack"
        case .offline: return "wand.and.stars"
        }
    }

    var summary: String {
        switch self {
        case .builtin: return "Free, open-source Qwen3.5 running on your iPhone. Private and offline."
        case .apple: return "Apple's on-device model (iOS 26, Apple Intelligence devices)."
        case .claude: return "Anthropic's Claude via your API key — the strongest option."
        case .openai: return "Ollama, LM Studio, OpenRouter or any /v1/chat/completions server."
        case .offline: return "Instant rule-based builder with no model. Always available."
        }
    }
}

/// Open-source GGUF models that run on device with llama.cpp.
struct LocalModel: Identifiable, Hashable {
    let id: String
    let name: String
    let file: String
    let url: URL
    let bytes: Int64
    let minRAMGB: Double
    let summary: String
    let license = "Apache-2.0"

    static let bundled = LocalModel(id: "qwen3.5-2b", name: "Qwen3.5 2B", file: "Qwen3.5-2B-Q4_K_M.gguf",
                                    url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf")!,
                                    bytes: 1_280_835_840, minRAMGB: 5.5, summary: "Included in the full IPA. Balanced quality and speed.")
    static let small = LocalModel(id: "qwen3.5-0.8b", name: "Qwen3.5 0.8B", file: "Qwen3.5-0.8B-Q4_K_M.gguf",
                                  url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf")!,
                                  bytes: 532_517_120, minRAMGB: 3, summary: "Fastest. For older iPhones with 4 GB of memory.")
    static let large = LocalModel(id: "qwen3.5-4b", name: "Qwen3.5 4B", file: "Qwen3.5-4B-Q4_K_M.gguf",
                                  url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf")!,
                                  bytes: 2_740_937_888, minRAMGB: 7.5, summary: "Smartest local model. iPhone 16 Pro / 17 and newer.")
    static let catalog = [bundled, small, large]

    static func find(_ id: String) -> LocalModel? { catalog.first { $0.id == id } }

    /// Bundled copy (full IPA) or downloaded copy.
    var localURL: URL? {
        if let b = Bundle.main.url(forResource: (file as NSString).deletingPathExtension, withExtension: "gguf", subdirectory: "Models") { return b }
        let d = Paths.models.appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: d.path) { return d }
        if let env = ProcessInfo.processInfo.environment["REYFORGE_MODEL_PATH"], env.hasSuffix(file), FileManager.default.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        return nil
    }

    var isBundled: Bool { Bundle.main.url(forResource: (file as NSString).deletingPathExtension, withExtension: "gguf", subdirectory: "Models") != nil }

    static var deviceRAMGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }
    var fitsDevice: Bool { LocalModel.deviceRAMGB + 0.4 >= minRAMGB }
}

/// Downloads models with progress (resumes are handled by re-starting the transfer).
@MainActor
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader()
    @Published var progress: [String: Double] = [:]
    @Published var errors: [String: String] = [:]
    private var tasks: [Int: LocalModel] = [:]
    private lazy var session: URLSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    func isDownloading(_ m: LocalModel) -> Bool { progress[m.id] != nil }

    func start(_ m: LocalModel) {
        guard progress[m.id] == nil else { return }
        errors[m.id] = nil
        progress[m.id] = 0
        let t = session.downloadTask(with: m.url)
        tasks[t.taskIdentifier] = m
        t.resume()
    }

    func cancel(_ m: LocalModel) {
        session.getAllTasks { all in
            Task { @MainActor in
                for t in all where self.tasks[t.taskIdentifier]?.id == m.id { t.cancel() }
                self.progress[m.id] = nil
            }
        }
    }

    func delete(_ m: LocalModel) {
        try? FileManager.default.removeItem(at: Paths.models.appendingPathComponent(m.file))
        objectWillChange.send()
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        MainActor.assumeIsolated {
            guard let m = tasks[id] else { return }
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : m.bytes
            progress[m.id] = min(1, Double(totalBytesWritten) / Double(max(total, 1)))
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move synchronously: the temporary file is deleted when this method returns.
        let id = downloadTask.taskIdentifier
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(id).gguf")
        try? FileManager.default.removeItem(at: staged)
        try? FileManager.default.moveItem(at: location, to: staged)
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        MainActor.assumeIsolated {
            guard let m = tasks[id] else { return }
            let dest = Paths.models.appendingPathComponent(m.file)
            if (200..<300).contains(status), let head = try? FileHandle(forReadingFrom: staged).readData(ofLength: 4), head == Data("GGUF".utf8) {
                try? FileManager.default.removeItem(at: dest)
                do { try FileManager.default.moveItem(at: staged, to: dest) } catch { errors[m.id] = error.localizedDescription }
            } else {
                errors[m.id] = "Download failed (HTTP \(status))."
                try? FileManager.default.removeItem(at: staged)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        MainActor.assumeIsolated {
            guard let m = tasks[id] else { return }
            if let e = error as NSError?, e.code != NSURLErrorCancelled { errors[m.id] = e.localizedDescription }
            progress[m.id] = nil
            tasks[id] = nil
        }
    }
}

/// Creates and caches the engine selected in settings.
@MainActor
final class AIEngineManager: ObservableObject {
    static let shared = AIEngineManager()
    @Published private(set) var status = ""
    @Published private(set) var isLoading = false
    private var llama: LlamaEngine?
    private var llamaModelID: String?

    /// Returns nil for the offline design engine.
    func makeEngine(settings: AppSettings) async throws -> LLMEngine? {
        let kind = AIEngineKind(rawValue: settings.aiEngine) ?? .offline
        switch kind {
        case .offline:
            return nil
        case .builtin:
            guard let model = LocalModel.find(settings.localModelID) ?? LocalModel.catalog.first(where: { $0.localURL != nil }),
                  let url = model.localURL else {
                throw EngineError("No on-device model installed yet. Download one in AI Settings, or switch engines.")
            }
            if let l = llama, llamaModelID == model.id, l.isLoaded { return l }
            llama?.unload()
            let engine = LlamaEngine(modelURL: url, displayName: "\(model.name) (on device)")
            if LocalModel.deviceRAMGB < 6 { engine.contextLength = 3072 }
            isLoading = true
            status = "Loading \(model.name)…"
            defer { isLoading = false; status = "" }
            try await Task.detached(priority: .userInitiated) { try engine.load() }.value
            llama = engine
            llamaModelID = model.id
            return engine
        case .apple:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                guard AppleIntelligenceEngine.isAvailable else { throw EngineError(AppleIntelligenceEngine.unavailableReason) }
                return AppleIntelligenceEngine()
            }
            #endif
            throw EngineError("Apple Intelligence requires iOS 26 on a supported device.")
        case .claude:
            let key = settings.claudeAPIKey
            guard !key.isEmpty else { throw EngineError("Add your Anthropic API key in AI Settings to use Claude.") }
            return ClaudeEngine(apiKey: key, model: settings.claudeModel, effort: settings.claudeEffort)
        case .openai:
            guard let url = URL(string: settings.openAIBaseURL), url.scheme != nil else { throw EngineError("Enter a valid server URL in AI Settings.") }
            return OpenAICompatibleEngine(baseURL: url, apiKey: settings.openAIKey, model: settings.openAIModel, tier: .strong)
        }
    }

    func unloadLocalModel() {
        llama?.unload()
        llama = nil
        llamaModelID = nil
    }
}

#if canImport(FoundationModels)
/// Apple's on-device foundation model (iOS 26+). Used like the local models: the design engine
/// provides structure and the model provides content, answers and edits.
@available(iOS 26.0, *)
final class AppleIntelligenceEngine: LLMEngine {
    let id = "apple"
    let displayName = "Apple Intelligence"
    let tier: EngineTier = .local
    let supportsGrammar = false
    private var cancelled = false

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableReason: String {
        switch SystemLanguageModel.default.availability {
        case .available: return ""
        case .unavailable(let reason): return "Apple Intelligence is unavailable (\(reason)). Turn it on in Settings or pick another engine."
        }
    }

    func generate(_ request: LLMRequest, stream: LLMStream) async throws -> String {
        cancelled = false
        let session = LanguageModelSession(instructions: request.system)
        let prompt = request.messages.map { ($0.role == "assistant" ? "Assistant: " : "") + $0.content }.joined(separator: "\n\n")
        let options = GenerationOptions(temperature: request.temperature, maximumResponseTokens: max(256, request.maxTokens))
        let response = try await session.respond(to: prompt, options: options)
        if cancelled { throw CancellationError() }
        let text = response.content
        stream.onText(text)
        return text
    }

    func cancel() { cancelled = true }
}
#endif
