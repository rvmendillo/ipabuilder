import Foundation
import Security
import SwiftUI
import ReyForgeCore

/// File locations used by the builder. UI tests run against a throwaway folder.
enum Paths {
    static let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")

    static let root: URL = {
        let fm = FileManager.default
        let base: URL
        if isUITest {
            base = fm.temporaryDirectory.appendingPathComponent("ReyForgeUITest", isDirectory: true)
        } else {
            base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ReyForge", isDirectory: true)
        }
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static var projects: URL { folder("Projects") }
    static var signing: URL { folder("Signing") }
    static var models: URL { folder("Models") }
    /// Built IPAs are kept in Documents so they show up in the Files app.
    static var builds: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = isUITest ? root.appendingPathComponent("Builds", isDirectory: true) : docs.appendingPathComponent("Builds", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var work: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ReyForgeWork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func folder(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A fresh, empty temporary directory.
    static func scratch(_ name: String) -> URL {
        let url = work.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func resetForUITests() {
        guard isUITest else { return }
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}

/// Secrets (API keys, certificate passwords) live in the Keychain, with a defaults fallback for
/// builds whose signature lacks a keychain access group.
enum SecretStore {
    static let service = "com.rvmendillo.reyforge"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "secret.\(key)")
        guard let v = value, !v.isEmpty, let data = v.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(Data(v.utf8).base64EncodedString(), forKey: "secret.\(key)")
        }
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data {
            return String(data: d, encoding: .utf8)
        }
        if let b64 = UserDefaults.standard.string(forKey: "secret.\(key)"), let d = Data(base64Encoded: b64) {
            return String(data: d, encoding: .utf8)
        }
        return nil
    }
}

/// User preferences shared across the builder.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var aiEngine: String { didSet { d.set(aiEngine, forKey: "ai.engine") } }
    @Published var localModelID: String { didSet { d.set(localModelID, forKey: "ai.localModel") } }
    @Published var claudeModel: String { didSet { d.set(claudeModel, forKey: "ai.claudeModel") } }
    @Published var claudeEffort: String { didSet { d.set(claudeEffort, forKey: "ai.claudeEffort") } }
    @Published var openAIBaseURL: String { didSet { d.set(openAIBaseURL, forKey: "ai.openaiURL") } }
    @Published var openAIModel: String { didSet { d.set(openAIModel, forKey: "ai.openaiModel") } }
    @Published var showAIThinking: Bool { didSet { d.set(showAIThinking, forKey: "ai.showThinking") } }
    @Published var selectedSigningID: String { didSet { d.set(selectedSigningID, forKey: "sign.selected") } }
    @Published var updateOwner: String { didSet { d.set(updateOwner, forKey: "update.owner") } }
    @Published var updateRepo: String { didSet { d.set(updateRepo, forKey: "update.repo") } }
    @Published var preferLiteUpdates: Bool { didSet { d.set(preferLiteUpdates, forKey: "update.lite") } }
    @Published var snapToGrid: Bool { didSet { d.set(snapToGrid, forKey: "canvas.snap") } }
    @Published var showOnboarding: Bool { didSet { d.set(showOnboarding, forKey: "onboarding.show") } }

    var claudeAPIKey: String {
        get { SecretStore.get("claude.apiKey") ?? "" }
        set { SecretStore.set(newValue, for: "claude.apiKey"); objectWillChange.send() }
    }
    var openAIKey: String {
        get { SecretStore.get("openai.apiKey") ?? "" }
        set { SecretStore.set(newValue, for: "openai.apiKey"); objectWillChange.send() }
    }
    var githubToken: String {
        get { SecretStore.get("github.token") ?? "" }
        set { SecretStore.set(newValue, for: "github.token"); objectWillChange.send() }
    }

    private init() {
        let d = UserDefaults.standard
        if Paths.isUITest {
            for key in ["ai.engine", "ai.localModel", "sign.selected", "onboarding.show"] { d.removeObject(forKey: key) }
        }
        aiEngine = d.string(forKey: "ai.engine") ?? (Paths.isUITest ? AIEngineKind.offline.rawValue : AIEngineKind.builtin.rawValue)
        localModelID = d.string(forKey: "ai.localModel") ?? LocalModel.bundled.id
        claudeModel = d.string(forKey: "ai.claudeModel") ?? ClaudeEngine.models[0]
        claudeEffort = d.string(forKey: "ai.claudeEffort") ?? "medium"
        openAIBaseURL = d.string(forKey: "ai.openaiURL") ?? "http://localhost:11434/v1"
        openAIModel = d.string(forKey: "ai.openaiModel") ?? "qwen3:8b"
        showAIThinking = d.object(forKey: "ai.showThinking") as? Bool ?? true
        selectedSigningID = d.string(forKey: "sign.selected") ?? ""
        updateOwner = d.string(forKey: "update.owner") ?? "rvmendillo"
        updateRepo = d.string(forKey: "update.repo") ?? "ipabuilder"
        preferLiteUpdates = d.object(forKey: "update.lite") as? Bool ?? true
        snapToGrid = d.object(forKey: "canvas.snap") as? Bool ?? true
        showOnboarding = Paths.isUITest ? false : (d.object(forKey: "onboarding.show") as? Bool ?? true)
    }
}

/// ReyForge's own brand colors.
enum RF {
    static let violet = Color(red: 0.424, green: 0.361, blue: 1.0)
    static let ember = Color(red: 1.0, green: 0.478, blue: 0.271)
    static let gradient = LinearGradient(colors: [violet, ember], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0"
    static let appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
}

extension Date {
    var relative: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}

extension Int64 {
    var byteString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
