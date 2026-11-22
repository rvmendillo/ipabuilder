import SwiftUI
import ReyForgeCore

/// Vibe coding: describe what you want and ReyForge AI builds screens, elements and logic.
struct AIPanel: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var chat: AIChatController
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var engines = AIEngineManager.shared
    @FocusState private var focused: Bool
    @State private var showScript = false
    @State private var showEngineSettings = false

    init(editor: EditorModel) {
        self.editor = editor
        self.chat = editor.chat
    }

    var engineKind: AIEngineKind { AIEngineKind(rawValue: settings.aiEngine) ?? .offline }

    var body: some View {
        VStack(spacing: 0) {
            engineBar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if chat.turns.isEmpty { welcome }
                        ForEach(chat.turns) { turn in
                            ChatBubble(turn: turn, canUndo: chat.appliedTurns.contains(turn.id) && turn.id == chat.turns.last?.id && editor.canUndo,
                                       showThinking: settings.showAIThinking) { chat.undo(turn) } onSuggestion: { chat.send($0) }
                                .id(turn.id)
                        }
                        if chat.isRunning { liveBubble.id("live") }
                        Color.clear.frame(height: 4).id("bottom")
                    }
                    .padding(14)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.turns.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: chat.liveText.count + chat.liveScript.count / 40 + chat.plan.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            if !chat.isRunning && !chat.suggestions.isEmpty { suggestionChips }
            inputBar
        }
        .sheet(isPresented: $showScript) { NavigationStack { ScriptConsole(editor: editor) } }
        .sheet(isPresented: $showEngineSettings) { NavigationStack { AISettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showEngineSettings = false } } } } }
    }

    var engineBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(AIEngineKind.allCases) { k in
                    Button { settings.aiEngine = k.rawValue } label: { Label(k.title, systemImage: settings.aiEngine == k.rawValue ? "checkmark" : k.symbol) }
                }
                Divider()
                Button { showEngineSettings = true } label: { Label("AI Settings…", systemImage: "gearshape") }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: engineKind.symbol)
                    Text(engineTitle).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
            .accessibilityIdentifier("ai.engine")
            if engines.isLoading { ProgressView().controlSize(.small); Text(engines.status).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            Button { showScript = true } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                .accessibilityLabel("Script console")
            Menu {
                Button(role: .destructive) { chat.clear() } label: { Label("Clear conversation", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    var engineTitle: String {
        switch engineKind {
        case .builtin: return LocalModel.find(settings.localModelID)?.name ?? "Built-in model"
        case .claude: return "Claude"
        default: return engineKind.title
        }
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(RF.gradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ReyForge AI").font(.headline)
                    Text("Describe screens, features or changes. I'll build them and explain what changed.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(Knowledge.greeting(project: editor.project)).font(.subheadline)
            if let s = editor.selectedNode {
                Label("Selected: \(s.displayName) — say “make it bigger”, “add a tap action”…", systemImage: "cursorarrow.rays")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    var liveBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(chat.status.isEmpty ? "Working…" : chat.status).font(.subheadline.weight(.medium))
            }
            if !chat.plan.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(chat.plan.enumerated()), id: \.offset) { _, step in
                        Label(step, systemImage: "circle.dashed").font(.caption)
                    }
                }
            }
            if settings.showAIThinking && !chat.liveThinking.isEmpty {
                Text(chat.liveThinking.suffix(400)).font(.caption).italic().foregroundStyle(.secondary)
            }
            if !chat.liveText.isEmpty { Text(chat.liveText).font(.subheadline) }
            if !chat.liveScript.isEmpty {
                Text(chat.liveScript.suffix(900))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chat.suggestions.prefix(4), id: \.self) { s in
                    Button { chat.send(s) } label: {
                        Text(s).font(.caption).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().stroke(Color.accentColor.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
    }

    var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(editor.selectedNode == nil ? "Describe what to build…" : "Change the selected element…", text: $chat.draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
                .submitLabel(.send)
                .onSubmit { chat.send() }
                .accessibilityIdentifier("ai.input")
            if chat.isRunning {
                Button { chat.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 30)) }
                    .tint(.red)
                    .accessibilityLabel("Stop")
            } else {
                Button { focused = false; chat.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }
                    .disabled(chat.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("ai.send")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct ChatBubble: View {
    let turn: ChatTurn
    let canUndo: Bool
    let showThinking: Bool
    let onUndo: () -> Void
    let onSuggestion: (String) -> Void
    @State private var showCode = false

    var body: some View {
        if turn.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(turn.text)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if showThinking, let t = turn.thinking, !t.isEmpty {
                    DisclosureGroup("Thinking") { Text(t).font(.caption).foregroundStyle(.secondary) }.font(.caption)
                }
                Text(LocalizedStringKey(turn.text)).font(.subheadline).textSelection(.enabled)
                    .accessibilityIdentifier("ai.reply")
                if !turn.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(turn.highlights, id: \.self) { h in
                            Label { Text(LocalizedStringKey(h)) } icon: { Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.multicolor) }
                                .font(.caption)
                        }
                    }
                }
                if let script = turn.script, !script.isEmpty {
                    DisclosureGroup(isExpanded: $showCode) {
                        ScrollView(.horizontal) {
                            Text(script).font(.caption.monospaced()).textSelection(.enabled).padding(8)
                        }
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
                        Button { UIPasteboard.general.string = script } label: { Label("Copy script", systemImage: "doc.on.doc") }.font(.caption)
                    } label: {
                        Label("ReyForge Script (\(script.split(separator: "\n").count) lines)", systemImage: "chevron.left.forwardslash.chevron.right").font(.caption)
                    }
                }
                HStack(spacing: 12) {
                    if let e = turn.engine { Text(e).font(.caption2).foregroundStyle(.tertiary) }
                    Spacer()
                    if canUndo { Button("Undo", action: onUndo).font(.caption.weight(.semibold)).buttonStyle(.borderless) }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
    }
}

/// Run ReyForge Script directly — the same language the AI writes.
struct ScriptConsole: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) var dismiss
    @State private var script = """
    SCREEN "Profile" tab icon=person.crop.circle
      AVATAR name="Alex Rivera" size=88
      HEADING "Alex Rivera"
      BUTTON "Edit profile" style=prominent -> toast "Saved!"
    """
    @State private var output = ""
    @State private var showReference = false

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $script)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
            Divider()
            ScrollView {
                Text(output.isEmpty ? "Output appears here." : output)
                    .font(.caption.monospaced())
                    .foregroundStyle(output.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 150)
            .background(Color(.secondarySystemBackground))
        }
        .navigationTitle("Script Console")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let r = editor.runScript(script)
                    var lines = r.changes.map { "✓ \($0.summary)" }
                    lines += r.warnings.map { "⚠️ \($0)" }
                    if let reply = r.reply { lines.append("💬 \(reply)") }
                    output = lines.isEmpty ? "No changes." : lines.joined(separator: "\n")
                } label: { Label("Run", systemImage: "play.fill") }
            }
            ToolbarItem(placement: .bottomBar) {
                Button { showReference = true } label: { Label("Language reference", systemImage: "book") }
            }
        }
        .sheet(isPresented: $showReference) {
            NavigationStack {
                ScrollView { Text(Prompts.languageReference).font(.caption.monospaced()).textSelection(.enabled).padding() }
                    .navigationTitle("ReyForge Script")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showReference = false } } }
            }
        }
    }
}
