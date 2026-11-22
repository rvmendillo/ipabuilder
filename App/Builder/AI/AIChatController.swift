import Foundation
import SwiftUI
import ReyForgeCore

/// The vibe-coding conversation for one project: sends requests to ReyForge AI and applies results.
@MainActor
final class AIChatController: ObservableObject {
    weak var editor: EditorModel?
    @Published var turns: [ChatTurn] = []
    @Published var draft = ""
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""
    @Published private(set) var plan: [String] = []
    @Published private(set) var liveText = ""
    @Published private(set) var liveScript = ""
    @Published private(set) var liveThinking = ""
    @Published var engineNotice: String?
    /// Index of the undo step created by each assistant turn (to offer "Undo").
    @Published private(set) var appliedTurns: Set<UUID> = []

    private var task: Task<Void, Never>?
    private var engine: LLMEngine?
    private let historyURL: URL?

    init(editor: EditorModel) {
        self.editor = editor
        historyURL = editor.library.folder(for: editor.project.id).appendingPathComponent("chat.json")
        if let url = historyURL, let d = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([ChatTurn].self, from: d) {
            turns = saved
        }
    }

    var suggestions: [String] {
        if let last = turns.last(where: { $0.role == .assistant }), !last.suggestions.isEmpty { return last.suggestions }
        guard let p = editor?.project else { return [] }
        return Knowledge.starterSuggestions(p)
    }

    func send(_ text: String? = nil) {
        let message = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isRunning, let editor = editor else { return }
        draft = ""
        turns.append(ChatTurn(role: .user, text: message))
        isRunning = true
        status = "Thinking…"
        plan = []
        liveText = ""
        liveScript = ""
        liveThinking = ""
        engineNotice = nil
        let history = Array(turns.dropLast().suffix(10))
        let project = editor.project
        let context = editor.context
        task = Task { [weak self] in
            guard let self = self else { return }
            var engine: LLMEngine?
            do {
                engine = try await AIEngineManager.shared.makeEngine(settings: AppSettings.shared)
            } catch {
                self.engineNotice = "\(error.localizedDescription) Using the offline design engine instead."
            }
            self.engine = engine
            let agent = VibeAgent(engine: engine)
            let result = await agent.respond(to: message, project: project, context: context, history: history) { [weak self] event in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
            }
            // Let queued stream events land before finishing.
            await Task.yield()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.finish(result, request: message) } }
        }
    }

    func stop() {
        engine?.cancel()
        task?.cancel()
        isRunning = false
        status = ""
        turns.append(ChatTurn(role: .assistant, text: "Stopped."))
        save()
    }

    private func handle(_ event: AgentEvent) {
        guard isRunning else { return }
        switch event {
        case .status(let s): status = s
        case .plan(let steps): plan = steps
        case .scriptDelta(let d): liveScript += d
        case .textDelta(let d): liveText += d
        case .thinkingDelta(let d): liveThinking += d
        }
    }

    private func finish(_ r: AgentResult, request: String) {
        guard isRunning else { return }
        isRunning = false
        status = ""
        var text = r.reply
        if let notice = engineNotice { text = "_\(notice)_\n\n" + text }
        if !r.warnings.isEmpty { text += "\n\n" + r.warnings.prefix(3).map { "⚠️ \($0)" }.joined(separator: "\n") }
        let turn = ChatTurn(role: .assistant, text: text, script: r.script.isEmpty ? nil : r.script, highlights: r.highlights,
                            suggestions: r.suggestions, engine: r.engineName, thinking: liveThinking.isEmpty ? nil : liveThinking)
        if let p = r.project, let editor = editor {
            let short = request.count > 32 ? String(request.prefix(32)) + "…" : request
            editor.replaceProject(p, label: "AI: \(short)")
            if let s = r.focusScreenID, p.screen(id: s) != nil { editor.showScreen(s) }
            if let n = r.focusNodeID, p.node(id: n) != nil { editor.selection = n }
            appliedTurns.insert(turn.id)
            Haptics.success()
        }
        turns.append(turn)
        liveText = ""
        liveScript = ""
        liveThinking = ""
        plan = []
        save()
    }

    func undo(_ turn: ChatTurn) {
        guard appliedTurns.contains(turn.id), turn.id == turns.last?.id, let editor = editor, editor.canUndo else { return }
        editor.undo()
        appliedTurns.remove(turn.id)
        turns.append(ChatTurn(role: .assistant, text: "Undid that change."))
        save()
    }

    func clear() {
        turns = []
        appliedTurns = []
        save()
    }

    private func save() {
        guard let url = historyURL else { return }
        let keep = Array(turns.suffix(60))
        if let d = try? JSONEncoder().encode(keep) { try? d.write(to: url, options: .atomic) }
    }
}
