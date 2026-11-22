import Foundation

// MARK: - Chat model

public struct ChatTurn: Codable, Hashable, Identifiable {
    public enum Role: String, Codable { case user, assistant }
    public var id: UUID
    public var role: Role
    public var text: String
    public var script: String?
    public var highlights: [String]
    public var suggestions: [String]
    public var engine: String?
    public var thinking: String?
    public var date: Date
    public init(role: Role, text: String, script: String? = nil, highlights: [String] = [], suggestions: [String] = [], engine: String? = nil, thinking: String? = nil) {
        self.id = UUID(); self.role = role; self.text = text; self.script = script; self.highlights = highlights
        self.suggestions = suggestions; self.engine = engine; self.thinking = thinking; self.date = Date()
    }
}

public enum AgentEvent {
    case status(String)
    case plan([String])
    case scriptDelta(String)
    case textDelta(String)
    case thinkingDelta(String)
}

public struct AgentResult {
    public var project: Project?
    public var reply: String
    public var highlights: [String]
    public var script: String
    public var changes: [ChangeRecord]
    public var suggestions: [String]
    public var engineName: String
    public var focusScreenID: String?
    public var focusNodeID: String?
    public var warnings: [String]
    public var intent: Intent
}

// MARK: - Agent

/// ReyForge AI: understands a request, plans, writes ReyForge Script (with the design engine and/or an LLM),
/// applies it to the project and explains what changed — like a coding assistant, but for app UI.
public final class VibeAgent {
    public var engine: LLMEngine?
    public var allowStrongFullScripts = true
    public init(engine: LLMEngine? = nil) { self.engine = engine }

    public var engineName: String { engine?.displayName ?? "ReyForge Design Engine (offline)" }

    public func respond(to message: String, project: Project, context: EditorContext = EditorContext(), history: [ChatTurn] = [],
                        events: @escaping (AgentEvent) -> Void = { _ in }) async -> AgentResult {
        let intent = RequestAnalyzer.analyze(message, project: project, context: context)
        events(.status("Understanding your request"))

        switch intent.operation {
        case .greeting:
            return reply(intent, text: Knowledge.greeting(project: project), suggestions: Knowledge.starterSuggestions(project))
        case .question:
            return await answer(message, intent: intent, project: project, context: context, history: history, events: events)
        default: break
        }

        var script = ""
        var usedEngine = "ReyForge Design Engine"
        var say: String?

        // Strong engines write the whole script; the design engine is the fallback.
        if let engine = engine, engine.tier == .strong, allowStrongFullScripts {
            events(.plan(Planner.plan(for: intent, project: project)))
            events(.status("Designing with \(engine.displayName)"))
            do {
                let request = LLMRequest(system: Prompts.fullSystem, messages: Prompts.historyMessages(history) + [
                    LLMMessage(role: "user", content: Prompts.userTurn(message, project: project, context: context, hint: Planner.outline(for: intent, project: project)))
                ], maxTokens: 4000, temperature: 0.3)
                let raw = try await engine.generate(request, stream: LLMStream(onText: { events(.scriptDelta($0)) }, onThinking: { events(.thinkingDelta($0)) }))
                (script, say) = Prompts.splitSay(raw)
                usedEngine = engine.displayName
            } catch {
                events(.status("\(engine.displayName) unavailable — using the offline design engine (\(error.localizedDescription))"))
            }
            let trial = RFSCompiler.compile(script, into: project, context: context)
            if trial.isEmpty { script = ""; say = nil }
        }

        if script.isEmpty {
            events(.plan(Planner.plan(for: intent, project: project)))
            script = await designEngineScript(intent, message: message, project: project, context: context, events: events)
            if engine != nil && engine?.tier == .local { usedEngine = "ReyForge Design Engine + \(engine!.displayName)" }
        }

        if script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Nothing understood: let a local model try a free-form element script, else explain.
            if let engine = engine, engine.tier == .local {
                script = await localElements(message, project: project, context: context, engine: engine, events: events)
                usedEngine = engine.displayName
            }
            if script.isEmpty {
                return reply(intent, text: Knowledge.notUnderstood(message), suggestions: Knowledge.starterSuggestions(project))
            }
        }

        events(.status("Building components"))
        let compiled = RFSCompiler.compile(script, into: project, context: context)
        if compiled.isEmpty {
            return reply(intent, text: Knowledge.notUnderstood(message) + (compiled.warnings.isEmpty ? "" : "\n\n" + compiled.warnings.prefix(3).joined(separator: "\n")),
                         suggestions: Knowledge.starterSuggestions(project), script: script)
        }
        events(.status("Applied \(compiled.changes.count) change\(compiled.changes.count == 1 ? "" : "s")"))
        let summary = Summarizer.summarize(intent: intent, result: compiled, before: project, say: say ?? compiled.reply)
        return AgentResult(project: compiled.project, reply: summary.text, highlights: summary.highlights, script: script, changes: compiled.changes,
                           suggestions: summary.suggestions, engineName: usedEngine, focusScreenID: compiled.focusScreenID,
                           focusNodeID: compiled.focusNodeID, warnings: compiled.warnings, intent: intent)
    }

    func reply(_ intent: Intent, text: String, suggestions: [String], script: String = "") -> AgentResult {
        AgentResult(project: nil, reply: text, highlights: [], script: script, changes: [], suggestions: suggestions, engineName: engineName,
                    focusScreenID: nil, focusNodeID: nil, warnings: [], intent: intent)
    }

    // MARK: Questions

    func answer(_ message: String, intent: Intent, project: Project, context: EditorContext, history: [ChatTurn], events: @escaping (AgentEvent) -> Void) async -> AgentResult {
        let local = Knowledge.answer(message)
        guard let engine = engine else {
            return reply(intent, text: local ?? Knowledge.capabilities, suggestions: Knowledge.starterSuggestions(project))
        }
        events(.status("Thinking"))
        do {
            let request = LLMRequest(system: Prompts.answerSystem(knowledge: local), messages: Prompts.historyMessages(history) + [
                LLMMessage(role: "user", content: "Project: \(Prompts.projectSummary(project, context: context, detail: false))\n\nQuestion: \(message)")
            ], maxTokens: engine.tier == .local ? 320 : 1500, temperature: 0.4)
            let text = try await engine.generate(request, stream: LLMStream(onText: { events(.textDelta($0)) }, onThinking: { events(.thinkingDelta($0)) }))
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return reply(intent, text: cleaned.isEmpty ? (local ?? Knowledge.capabilities) : cleaned, suggestions: Knowledge.starterSuggestions(project))
        } catch {
            return reply(intent, text: local ?? Knowledge.capabilities, suggestions: Knowledge.starterSuggestions(project))
        }
    }

    // MARK: Design engine (+ local model for content)

    func pack(for intent: Intent, project: Project) -> ContentPack {
        if let d = intent.domain { return ContentPacks.pack(d) }
        if let t = intent.topic { return ContentPacks.personalized(topic: t) }
        // Fall back to the project's own topic.
        if let d = ContentPacks.detect(project.name + " " + project.brand.tagline) { return ContentPacks.pack(d) }
        if let d = project.screens.lazy.compactMap({ ContentPacks.detect($0.name) }).first { return ContentPacks.pack(d) }
        return ContentPacks.pack(.generic)
    }

    /// Asks a local model for topic-specific content when no curated pack fits.
    func enrich(_ pack: ContentPack, topic: String?, events: @escaping (AgentEvent) -> Void) async -> ContentPack {
        guard let engine = engine, engine.tier == .local, let topic = topic, ContentPacks.detect(topic) == nil else { return pack }
        events(.status("Writing \(topic) content with \(engine.displayName)"))
        let request = LLMRequest(system: Prompts.contentSystem, messages: [LLMMessage(role: "user", content: "Topic: \(topic) app\nDashboard content")],
                                 grammar: engine.supportsGrammar ? Grammars.content : nil, maxTokens: 420, temperature: 0.3)
        guard let raw = try? await engine.generate(request, stream: LLMStream(onText: { events(.scriptDelta($0)) })),
              let json = Value.fromJSONString(Prompts.extractJSON(raw)) else { return pack }
        return ContentEnricher.apply(json, to: pack)
    }

    func designEngineScript(_ intent: Intent, message: String, project: Project, context: EditorContext, events: @escaping (AgentEvent) -> Void) async -> String {
        switch intent.operation {
        case .createApp:
            var pack = pack(for: intent, project: project)
            pack = await enrich(pack, topic: intent.topic, events: events)
            let lower = message.lowercased()
            var screens: [(Archetype, String)]?
            let explicit = intent.archetypes.filter { ![.login, .signup, .onboarding].contains($0) }
            if explicit.count >= 2 { screens = explicit.prefix(5).map { ($0, $0.defaultName) } }
            events(.status("Laying out \(pack.appName)"))
            return Recipes.app(pack: pack, name: intent.appName, screens: screens,
                               includeLogin: intent.archetypes.contains(.login) || lower.contains("login") || lower.contains("sign in") || lower.contains("accounts"),
                               includeOnboarding: intent.archetypes.contains(.onboarding) || lower.contains("onboarding"))
        case .createScreen:
            var pack = pack(for: intent, project: project)
            pack = await enrich(pack, topic: intent.topic, events: events)
            var w = RFSWriter()
            let home = project.navigation.tabs.first.map { project.screenName($0.screenID) } ?? project.initialScreen?.name ?? "Home"
            let archetypes = intent.archetypes.isEmpty ? [Archetype.dashboard] : intent.archetypes
            for (i, a) in archetypes.prefix(4).enumerated() {
                var name = (i == 0 ? intent.screenName : nil) ?? a.defaultName
                if project.screen(named: name) != nil && !message.lowercased().contains("replace") && !message.lowercased().contains("redesign") {
                    name = project.uniqueScreenName(name)
                }
                let asTab = intent.asTab || (project.navigation.style == .tabs && ![.login, .signup, .onboarding, .detail, .checkout, .product, .conversation].contains(a))
                events(.status("Designing the \(name) screen"))
                Recipes.build(a, pack: pack, options: RecipeOptions(screenName: name, tab: asTab, appName: project.brand.displayName, homeScreen: home, requested: intent.components), into: &w)
                for req in intent.components where !Planner.recipeCovers(a, req.type) {
                    RulesEngine.elementLines(req, pack: pack, into: &w, indent: 1)
                }
            }
            if message.lowercased().contains("redesign") || message.lowercased().contains("replace"), let first = w.lines.firstIndex(where: { $0.hasPrefix("SCREEN ") }) {
                w = RFSWriter(lines: w.lines.enumerated().map { $0.offset == first ? $0.element + " replace" : $0.element })
            }
            return w.text
        case .addElements:
            let rules = RulesEngine.additions(intent, pack: pack(for: intent, project: project)) ?? ""
            // Precise requests ("add a toggle for Wi-Fi") are handled exactly; descriptive ones benefit from the model.
            let precise = intent.raw.lowercased().contains("counter") || intent.raw.split(separator: " ").count <= 6
                || intent.components.allSatisfy { $0.label != nil || [.divider, .spacer, .searchField, .signInApple, .map, .qr].contains($0.type) }
            if !precise, let engine = engine, engine.tier == .local {
                let llm = await localElements(message, project: project, context: context, engine: engine, events: events)
                if !RFSCompiler.compile(llm, into: project, context: context).isEmpty { return llm }
            }
            if !rules.isEmpty { return rules }
            if let engine = engine, engine.tier == .local { return await localElements(message, project: project, context: context, engine: engine, events: events) }
            return ""
        case .edit:
            if let s = RulesEngine.edit(intent, project: project, context: context) { return s }
            if let engine = engine, engine.tier == .local { return await localEdit(message, project: project, context: context, engine: engine, events: events) }
            return ""
        case .delete:
            return RulesEngine.delete(intent, project: project, context: context) ?? ""
        case .theme:
            return RulesEngine.theme(intent)
        case .logic:
            return RulesEngine.logic(intent, project: project, context: context) ?? ""
        case .unknown:
            if let engine = engine, engine.tier == .local { return await localElements(message, project: project, context: context, engine: engine, events: events) }
            return ""
        case .question, .greeting:
            return ""
        }
    }

    func localElements(_ message: String, project: Project, context: EditorContext, engine: LLMEngine, events: @escaping (AgentEvent) -> Void) async -> String {
        events(.status("Writing elements with \(engine.displayName)"))
        let intent = RequestAnalyzer.analyze(message, project: project, context: context)
        let allowed = Prompts.allowedKeywords(for: intent)
        let screen = context.screenID.flatMap { project.screen(id: $0) }?.name ?? project.initialScreen?.name ?? "Home"
        var turn = "App \(rq(project.brand.displayName)), screen \(rq(screen)).\nRequest: \(message)"
        if !allowed.isEmpty { turn += "\nElements to use: " + allowed.prefix(3).joined(separator: ", ") }
        let request = LLMRequest(system: Prompts.elementsSystem, messages: [LLMMessage(role: "user", content: turn)],
                                 grammar: engine.supportsGrammar ? Grammars.elements(allowing: allowed) : nil, maxTokens: 360, temperature: 0.2, stopSequences: ["END"])
        guard let raw = try? await engine.generate(request, stream: LLMStream(onText: { events(.scriptDelta($0)) })) else { return "" }
        return Prompts.splitSay(raw).script
    }

    func localEdit(_ message: String, project: Project, context: EditorContext, engine: LLMEngine, events: @escaping (AgentEvent) -> Void) async -> String {
        events(.status("Working out the change with \(engine.displayName)"))
        let request = LLMRequest(system: Prompts.editSystem, messages: [
            LLMMessage(role: "user", content: Prompts.userTurn(message, project: project, context: context, hint: nil))
        ], grammar: engine.supportsGrammar ? Grammars.edit : nil, maxTokens: 160, temperature: 0.1, stopSequences: ["END"])
        guard let raw = try? await engine.generate(request, stream: LLMStream(onText: { events(.scriptDelta($0)) })) else { return "" }
        return Prompts.splitSay(raw).script
    }
}

extension RFSWriter {
    init(lines: [String]) { self.init(); for l in lines { add(0, l) } }
}

// MARK: - Planner (visible plan steps, like a coding assistant)

public enum Planner {
    public static func plan(for intent: Intent, project: Project) -> [String] {
        switch intent.operation {
        case .createApp:
            let pack = intent.domain.map { ContentPacks.pack($0) }
            let screens = Recipes.blueprint(for: intent.domain ?? .generic).map { $0.1 }
            return ["Pick a brand and theme for \(intent.appName ?? pack?.appName ?? "your app")",
                    "Create \(screens.count) tab screens: \(screens.joined(separator: ", "))",
                    "Fill them with realistic \(intent.topic ?? intent.domain?.rawValue ?? "sample") content",
                    "Wire navigation, forms and list logic"]
        case .createScreen:
            let names = (intent.archetypes.isEmpty ? [.dashboard] : intent.archetypes).map { $0.defaultName }
            return ["Design the \(names.joined(separator: " & ")) layout", "Add native components and sample data", "Connect actions and variables"]
        case .addElements:
            return ["Choose components: " + intent.components.map { ComponentRegistry.spec(for: $0.type).title }.joined(separator: ", "), "Place them on the current screen"]
        case .edit: return ["Find the element", "Apply the changes"]
        case .delete: return ["Find the element", "Remove it"]
        case .theme: return ["Update theme colors and typography", "Refresh the app icon"]
        case .logic: return ["Find the trigger element", "Add the action flow"]
        default: return ["Read the request", "Update the app"]
        }
    }

    /// A short design outline given to strong models as a hint.
    public static func outline(for intent: Intent, project: Project) -> String? {
        guard intent.operation == .createScreen || intent.operation == .createApp else { return nil }
        let pack = intent.domain.map { ContentPacks.pack($0) }
        var parts: [String] = []
        if let p = pack { parts.append("Topic: \(p.domain.rawValue). Suggested app name \(p.appName), theme preset \(p.presetID).") }
        if !intent.archetypes.isEmpty { parts.append("Screens: " + intent.archetypes.map { $0.defaultName }.joined(separator: ", ")) }
        if !intent.components.isEmpty { parts.append("Must include: " + intent.components.map { ComponentRegistry.spec(for: $0.type).title + ($0.label.map { " “\($0)”" } ?? "") }.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func recipeCovers(_ a: Archetype, _ t: ComponentType) -> Bool {
        switch a {
        case .dashboard: return [.statCard, .chart, .list, .listRow, .button, .text, .gauge, .card, .grid].contains(t)
        case .settings: return [.toggle, .picker, .slider, .form, .section, .button, .navLink, .labeledContent, .link, .shareLink].contains(t)
        case .login, .signup: return [.textField, .secureField, .button, .signInApple, .text, .icon, .link, .toggle, .form, .section].contains(t)
        case .booking: return [.datePicker, .stepper, .picker, .map, .textField, .button, .form, .image].contains(t)
        case .cart: return [.list, .listRow, .button, .stepper, .labeledContent, .card].contains(t)
        case .store, .product: return [.grid, .card, .image, .searchField, .button, .stepper, .picker, .rating, .badge, .scroll].contains(t)
        case .profile: return [.avatar, .statCard, .button, .grid, .image, .list, .navLink, .text].contains(t)
        case .onboarding: return [.pager, .button, .icon, .text].contains(t)
        case .weather: return [.chart, .statCard, .list, .icon, .text, .button].contains(t)
        case .workout: return [.gauge, .timer, .picker, .stepper, .button].contains(t)
        case .todo: return [.list, .listRow, .textField, .button, .progress, .toggle].contains(t)
        default: return [.text, .button, .list, .listRow].contains(t)
        }
    }
}

// MARK: - Rules engine (deterministic edits, logic and additions)

public enum RulesEngine {
    static func target(_ intent: Intent, project: Project, context: EditorContext) -> String? {
        if intent.targetsSelection, context.selectedNodeID != nil { return "selected" }
        if let label = intent.targetLabel {
            if let t = intent.targetType { return "\(ComponentRegistry.spec(for: t).rfsKeyword) \(rq(label))" }
            return rq(label)
        }
        if let t = intent.targetType {
            let screenNodes = context.screenID.flatMap { project.screen(id: $0) }?.root.flattened ?? project.allNodes.map { $0.node }
            var candidates = screenNodes.filter { $0.type == t }
            if t == .text, intent.edits["_textStyle"] == "title" {
                candidates.sort { (FontSpec.textStyles.firstIndex(of: $0.style.font?.style ?? "body") ?? 6) < (FontSpec.textStyles.firstIndex(of: $1.style.font?.style ?? "body") ?? 6) }
            }
            if let n = candidates.first { return "#\(n.id)" }
        }
        if context.selectedNodeID != nil { return "selected" }
        return nil
    }

    public static func edit(_ intent: Intent, project: Project, context: EditorContext) -> String? {
        guard let t = target(intent, project: project, context: context) else { return nil }
        var parts: [String] = ["EDIT \(t)"]
        for (k, v) in intent.edits.sorted(by: { $0.key < $1.key }) where !k.hasPrefix("_") {
            if k == "text" { parts.append("title=\(rq(v))"); parts.append("text=\(rq(v))") }
            else { parts.append("\(k)=\(v.contains(" ") ? rq(v) : v)") }
        }
        parts += intent.editFlags
        return parts.count > 1 ? parts.joined(separator: " ") : nil
    }

    public static func delete(_ intent: Intent, project: Project, context: EditorContext) -> String? {
        if let screen = intent.edits["screen"] ?? (intent.raw.lowercased().contains("screen") ? intent.targetScreen : nil) { return "DELETE screen \(screen)" }
        guard let t = target(intent, project: project, context: context) else { return nil }
        return "DELETE \(t)"
    }

    public static func theme(_ intent: Intent) -> String {
        var parts = ["APP"]
        for (k, v) in intent.themeAttributes.sorted(by: { $0.key < $1.key }) { parts.append("\(k)=\(v.contains(" ") ? rq(v) : v)") }
        return parts.count > 1 ? parts.joined(separator: " ") : "APP theme=system"
    }

    public static func logic(_ intent: Intent, project: Project, context: EditorContext) -> String? {
        guard let t = target(intent, project: project, context: context), !intent.logicActions.isEmpty else { return nil }
        var lines: [String] = []
        if intent.logicActions.contains(where: { $0.hasPrefix("inc count") || $0.hasPrefix("dec count") }), project.variable(named: "count") == nil {
            lines.append("VAR count number 0")
        }
        lines.append("EDIT \(t) -> " + intent.logicActions.joined(separator: "; "))
        return lines.joined(separator: "\n")
    }

    public static func additions(_ intent: Intent, pack: ContentPack) -> String? {
        var w = RFSWriter()
        let lower = intent.raw.lowercased()
        if lower.contains("counter") {
            w.add(0, "VAR count number 0")
            w.add(0, "CARD align=center")
            w.add(1, "TEXT \"{{count}}\" fontsize=56 bold center")
            w.add(1, "HSTACK")
            w.add(2, "BUTTON \"−\" style=bordered -> dec count; haptic light")
            w.add(2, "BUTTON \"+\" style=prominent -> inc count; haptic light")
            w.add(1, "BUTTON \"Reset\" style=plain -> set count = 0")
            return w.text
        }
        guard !intent.components.isEmpty else { return nil }
        for req in intent.components { elementLines(req, pack: pack, into: &w, indent: 0) }
        return w.text
    }

    static func varName(_ label: String?, _ fallback: String) -> String { Variable.sanitize(label ?? fallback) }

    /// ReyForge Script for one requested element with sensible, topic-aware defaults.
    public static func elementLines(_ r: ComponentRequest, pack: ContentPack, into w: inout RFSWriter, indent i: Int) {
        let label = r.label
        let color = r.color.map { " color=\($0)" } ?? ""
        let size = r.size.map { " size=\($0 == "big" || $0 == "huge" ? "large" : $0)" } ?? ""
        let nav = r.navigateTo.map { " -> go \(rq($0))" }
        let n = max(1, min(r.count, 8))
        switch r.type {
        case .button:
            for k in 0..<n {
                let title = label ?? (n > 1 ? ["Continue", "Learn more", "Share", "Save"][k % 4] : "Continue")
                let icon = SymbolResolver.symbol(forConcept: title, fallback: "arrow.right.circle.fill")
                w.add(i, "BUTTON \(rq(title)) icon=\(icon) style=\(k == 0 ? "prominent" : "bordered") full\(color)\(size)\(nav ?? " -> haptic light; toast \(rq("\(title) tapped"))")")
            }
        case .toggle:
            for k in 0..<n {
                let title = label ?? ["Notifications", "Dark mode", "Location", "Sounds"][k % 4]
                w.add(i, "TOGGLE \(rq(title)) bind=\(varName(title, "isOn")) icon=\(SymbolResolver.symbol(forConcept: title, fallback: "switch.2"))\(color)")
            }
        case .slider: w.add(i, "SLIDER \(rq(label ?? "Volume")) bind=\(varName(label, "volume")) min=0 max=100 value=50\(color)")
        case .stepper: w.add(i, "STEPPER \(rq(label ?? "Quantity")) bind=\(varName(label, "quantity")) min=0 max=10 value=1")
        case .picker:
            let l = (label ?? "").lowercased()
            let options = l.contains("size") ? "S,M,L,XL" : (l.contains("theme") || l.contains("appearance") ? "System,Light,Dark" : (l.contains("day") ? "Mon,Tue,Wed,Thu,Fri" : pack.categories.prefix(4).joined(separator: ",")))
            w.add(i, "PICKER \(rq(label ?? "Category")) \(rq(options)) bind=\(varName(label, "selection")) style=\(r.keyword.contains("segment") ? "segmented" : "menu")")
        case .datePicker: w.add(i, "DATE \(rq(label ?? "Date")) bind=\(varName(label, "date"))\(r.keyword.contains("calendar") ? " style=graphical" : "")")
        case .colorPicker: w.add(i, "COLOR \(rq(label ?? "Color")) bind=\(varName(label, "color"))")
        case .textField:
            let l = (label ?? r.keyword).lowercased()
            let keyboard = l.contains("email") ? "email" : (l.contains("phone") ? "phone" : (l.contains("amount") || l.contains("price") ? "decimal" : (l.contains("url") || l.contains("website") ? "url" : "default")))
            let title = label ?? (r.keyword.contains("email") ? "Email" : (r.keyword.contains("name") ? "Name" : "Your answer"))
            w.add(i, "FIELD \(rq(title)) bind=\(varName(title, "text")) keyboard=\(keyboard)")
        case .secureField: w.add(i, "SECURE \(rq(label ?? "Password")) bind=\(varName(label, "password"))")
        case .textEditor: w.add(i, "EDITOR \(rq(label ?? "Notes")) bind=\(varName(label, "notes")) height=140")
        case .searchField: w.add(i, "SEARCH \(rq(label ?? "Search")) bind=query")
        case .menu:
            w.add(i, "MENU \(rq(label ?? "Options")) icon=ellipsis.circle")
            w.add(i + 1, "BUTTON \"Edit\" icon=pencil -> toast \"Edit\"")
            w.add(i + 1, "BUTTON \"Duplicate\" icon=plus.square.on.square -> toast \"Duplicated\"")
            w.add(i + 1, "BUTTON \"Delete\" icon=trash style=destructive -> toast \"Deleted\" \"warning\"")
        case .shareLink: w.add(i, "SHARE \(rq(label ?? "Share")) \(rq("Check out \(pack.appName)!"))")
        case .photoPicker: w.add(i, "PHOTO \(rq(label ?? "Choose photo")) bind=photo")
        case .signInApple: w.add(i, "APPLE -> haptic success; toast \"Signed in with Apple\"")
        case .text:
            let k = r.detail ?? r.keyword
            if k.contains("title") || k.contains("heading") || k.contains("headline") { w.add(i, "\(k.contains("title") ? "TITLE" : "HEADING") \(rq(label ?? pack.greeting))\(color)") }
            else if k.contains("caption") || k.contains("subtitle") { w.add(i, "CAPTION \(rq(label ?? pack.summary))") }
            else { w.add(i, "TEXT \(rq(label ?? pack.description))\(color)") }
        case .label: w.add(i, "LABEL \(rq(label ?? "Favorites")) icon=\(SymbolResolver.symbol(forConcept: label ?? "favorites", fallback: "star.fill"))\(color)")
        case .image: w.add(i, "IMAGE \(rq(label ?? pack.domain.rawValue)) height=\(r.keyword.contains("banner") || r.keyword.contains("hero") ? 220 : 180)")
        case .icon: w.add(i, "ICON \(rq(SymbolResolver.symbol(forConcept: label ?? "star", fallback: "star.fill"))) size=48\(color.isEmpty ? " color=accent" : color)")
        case .avatar: w.add(i, "AVATAR \(rq(label ?? "Alex Morgan")) size=64")
        case .badge: w.add(i, "BADGE \(rq(label ?? "New"))\(color)")
        case .divider: w.add(i, "DIVIDER")
        case .spacer: w.add(i, "SPACER 24")
        case .shape: w.add(i, "SHAPE \(r.keyword == "circle" ? "circle" : "rounded") width=120 height=\(r.keyword == "circle" ? 120 : 80)\(color.isEmpty ? " color=accent" : color)")
        case .gradient: w.add(i, "GRADIENT \"accent,secondary\" height=140")
        case .progress: w.add(i, "PROGRESS \(rq(label ?? "Progress")) value=0.6\(r.keyword.contains("spinner") ? " circular" : "")\(color)")
        case .gauge: w.add(i, "GAUGE \(rq(label ?? pack.gauge.label)) value=\(Value.format(number: pack.gauge.value)) max=100\(color)")
        case .chart: w.add(i, "CHART \(r.detail ?? pack.chartKind) \(rq(pack.chartData)) title=\(rq(label ?? pack.chartTitle)) height=200\(color)")
        case .map: w.add(i, "MAP \(rq(label ?? pack.place)) height=220")
        case .web: w.add(i, "WEB \(rq((label ?? "").contains(".") ? ((label ?? "").hasPrefix("http") ? label! : "https://" + label!) : "https://www.apple.com")) height=380")
        case .video: w.add(i, "VIDEO \"https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8\" height=220")
        case .audio: w.add(i, "AUDIO \"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3\" \(rq(label ?? "Now playing"))")
        case .statCard:
            let count = r.count > 1 ? r.count : (r.keyword.hasSuffix("s") ? 4 : 2)
            w.add(i, "GRID columns=2")
            for s in pack.stats.prefix(max(2, min(count, pack.stats.count))) { w.add(i + 1, "STAT \(rq(s.title)) \(rq(s.value)) icon=\(s.icon) delta=\(rq(s.delta))") }
        case .rating: w.add(i, "RATING value=4 bind=rating")
        case .timer: w.add(i, "TIMER 300\(r.keyword == "stopwatch" ? " stopwatch" : "")")
        case .empty: w.add(i, "EMPTY \(rq(label ?? "Nothing here yet")) icon=tray message=\"Items you add will appear here.\"")
        case .link: w.add(i, "LINK \(rq(label ?? "Learn more")) \"https://example.com\"")
        case .qr: w.add(i, "QR \(rq(label ?? "https://example.com")) size=180")
        case .list, .listRow:
            w.add(i, "LIST")
            for it in pack.items.prefix(r.type == .listRow ? n : 4) { w.add(i + 1, "ROW \(rq(it.title)) subtitle=\(rq(it.subtitle)) value=\(rq(it.value)) icon=\(it.icon)") }
        case .form, .section:
            if r.type == .form { w.add(i, "FORM") }
            let base = r.type == .form ? i + 1 : i
            w.add(base, "SECTION \(rq(label ?? "Details"))")
            w.add(base + 1, "FIELD \"Name\" bind=name")
            w.add(base + 1, "TOGGLE \"Remember me\" bind=rememberMe")
        case .card:
            for k in 0..<n {
                w.add(i, "CARD")
                w.add(i + 1, "HEADING \(rq(label ?? pack.items[k % pack.items.count].title))")
                w.add(i + 1, "CAPTION \(rq(pack.items[k % pack.items.count].subtitle))")
            }
        case .grid:
            w.add(i, "GRID columns=2")
            for s in pack.stats.prefix(4) {
                w.add(i + 1, "CARD")
                w.add(i + 2, "ICON \(rq(s.icon)) size=26 color=accent")
                w.add(i + 2, "TEXT \(rq(s.title)) bold")
                w.add(i + 2, "CAPTION \(rq(s.value))")
            }
        case .scroll:
            w.add(i, "SCROLL horizontal")
            for k in 0..<5 { w.add(i + 1, "IMAGE \"https://picsum.photos/seed/\(pack.domain.rawValue)c\(k)/500/350\" width=200 height=130 radius=14") }
        case .pager:
            w.add(i, "PAGER height=260")
            for (k, it) in pack.items.prefix(3).enumerated() {
                w.add(i + 1, "VSTACK align=center")
                w.add(i + 2, "ICON \(rq(it.icon)) size=56 color=accent")
                w.add(i + 2, "TEXT \(rq(it.title)) style=title3 bold center")
                w.add(i + 2, "CAPTION \"Page \(k + 1) of 3\" center")
            }
        case .navLink: w.add(i, "NAVLINK \(rq(label ?? "More details")) \(rq(r.navigateTo ?? label ?? "Details"))")
        case .labeledContent: w.add(i, "INFO \(rq(label ?? "Version")) \"1.0\"")
        case .disclosure:
            w.add(i, "DISCLOSURE \(rq(label ?? "More details"))")
            w.add(i + 1, "TEXT \(rq(pack.description)) color=secondaryText")
        case .groupBox:
            w.add(i, "GROUP \(rq(label ?? "Summary"))")
            w.add(i + 1, "TEXT \(rq(pack.summary))")
        case .vstack, .hstack, .zstack:
            w.add(i, r.type == .zstack ? "ZSTACK height=240" : (r.type == .hstack ? "HSTACK" : "VSTACK"))
            w.add(i + 1, "TEXT \(rq(label ?? "Item one"))")
            w.add(i + 1, "TEXT \"Item two\"")
        }
    }
}

// MARK: - Local-model content enrichment

public enum ContentEnricher {
    public static func apply(_ json: Value, to base: ContentPack) -> ContentPack {
        var p = base
        let stats = json["stats"].arrayValue.compactMap { s -> ContentPack.Stat? in
            let t = s["title"].stringValue, v = s["value"].stringValue
            guard !t.isEmpty, !v.isEmpty else { return nil }
            return .init(title: t, value: v, icon: SymbolResolver.resolve(s["icon"].stringValue, fallback: SymbolResolver.symbol(forConcept: t, fallback: base.symbol)), delta: "")
        }
        if stats.count >= 2 { p.stats = stats }
        let items = json["items"].arrayValue.compactMap { s -> ContentPack.Item? in
            let t = s["title"].stringValue
            guard !t.isEmpty else { return nil }
            return .init(title: t, subtitle: s["subtitle"].stringValue, value: s["value"].stringValue,
                         icon: SymbolResolver.resolve(s["icon"].stringValue, fallback: SymbolResolver.symbol(forConcept: t, fallback: base.symbol)))
        }
        if items.count >= 2 { p.items = items }
        let points = json["chart"]["points"].arrayValue.compactMap { pt -> (String, Double)? in
            guard let v = pt["value"].numberValue else { return nil }
            return (pt["label"].stringValue.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ":", with: " "), v)
        }
        if points.count >= 3 { p.chart = points; if !json["chart"]["title"].stringValue.isEmpty { p.chartTitle = json["chart"]["title"].stringValue } }
        return p
    }
}

// MARK: - Reply writer

public enum Summarizer {
    public struct Summary { public var text: String; public var highlights: [String]; public var suggestions: [String] }

    public static func summarize(intent: Intent, result: CompileResult, before: Project, say: String?) -> Summary {
        let p = result.project
        let newScreens = result.changes.filter { $0.kind == .addedScreen }.compactMap { $0.screenID }.compactMap { p.screen(id: $0) }
        let addedNodes = result.createdNodeIDs.compactMap { p.node(id: $0) }
        var opening: String
        switch intent.operation {
        case .createApp:
            let tabs = p.navigation.tabs.map { $0.title }
            opening = "I built **\(p.brand.displayName)**" + (tabs.isEmpty ? "." : " — a \(tabs.count)-tab app with \(listJoin(tabs)).")
        case .createScreen:
            // Screens with real content (link-target stubs that the script never filled are skipped).
            let primary = newScreens.filter { $0.root.flattened.count > 3 }
            if let main = primary.first {
                let parts = unique(main.root.flattened.dropFirst().compactMap { notableProse($0) })
                opening = "Here's your new **\(main.name)** screen" + (parts.isEmpty ? "." : " with \(listJoin(Array(parts.prefix(4)))).")
                let others = primary.dropFirst().map { "**\($0.name)**" }
                if !others.isEmpty { opening += " I also created \(listJoin(Array(others.prefix(4)))) so every button leads somewhere." }
            } else {
                opening = "I updated the screen."
            }
        case .addElements:
            let kinds = unique(addedNodes.filter { node in p.parent(of: node.id).map { !result.createdNodeIDs.contains($0.id) } ?? true }
                .map { ComponentRegistry.spec(for: $0.type).title.lowercased() })
            let screen = result.focusScreenID.flatMap { p.screen(id: $0)?.name } ?? "the screen"
            let topLevel = addedNodes.filter { node in p.parent(of: node.id).map { !result.createdNodeIDs.contains($0.id) } ?? true }
            // Name containers by their heading ("Added a Refund Policy card").
            let described: [String] = topLevel.prefix(5).map { node in
                let kind = ComponentRegistry.spec(for: node.type).title.lowercased()
                let heading = node.children.first { [.text, .label].contains($0.type) }.map { $0.string("text").isEmpty ? $0.string("title") : $0.string("text") }
                    ?? ([.button, .toggle, .slider, .stepper, .picker, .statCard].contains(node.type) ? node.string("title") : "")
                return heading.isEmpty || heading.contains("{{") ? article(kind) + " " + kind : "\(article(kind)) **\(heading)** \(kind)"
            }
            opening = kinds.isEmpty ? "Added the elements." : "Added \(listJoin(described)) to **\(screen)**."
        case .edit:
            let names = result.changes.filter { $0.kind == .updatedNode }.compactMap { $0.nodeID }.compactMap { p.node(id: $0)?.displayName }
            let what = describeEdits(intent)
            opening = "Updated \(names.isEmpty ? "the element" : "**\(names[0])**")" + (what.isEmpty ? "." : " — \(what).")
        case .delete:
            let removed = result.changes.filter { $0.kind == .removedNode }.map { $0.summary.replacingOccurrences(of: "Removed ", with: "").replacingOccurrences(of: "Deleted ", with: "") }
            opening = removed.isEmpty ? "Nothing matched, so nothing was removed." : "Removed \(listJoin(removed.map { "**\($0)**" }))."
        case .theme:
            opening = result.changes.first(where: { $0.kind == .theme })?.summary.replacingOccurrences(of: "Updated the theme:", with: "Restyled the app:") ?? "Updated the branding."
            if !opening.hasSuffix(".") { opening += "." }
        case .logic:
            let flows = result.changes.filter { $0.kind == .logic }.map { $0.summary.replacingOccurrences(of: "Wired actions: ", with: "") }
            let names = result.changes.filter { $0.kind == .updatedNode }.compactMap { $0.nodeID }.compactMap { p.node(id: $0)?.displayName }
            opening = "Wired it up: tapping **\(names.first ?? "the element")** now runs \(flows.first.map { "“\($0)”" } ?? "the new actions")."
        default:
            opening = "Done."
        }
        if let say = say?.trimmingCharacters(in: .whitespacesAndNewlines), !say.isEmpty { opening = say }

        var highlights: [String] = []
        if intent.operation == .createApp || intent.operation == .createScreen {
            for s in newScreens.prefix(8) {
                var notable = unique(s.root.flattened.dropFirst().compactMap { notableName($0) })
                if notable.contains("KPI cards") { notable.removeAll { $0 == "grid" } }
                guard !notable.isEmpty || p.isTab(s.id) else { continue }
                highlights.append("**\(s.name)**" + (p.isTab(s.id) ? " (tab)" : "") + (notable.isEmpty ? "" : " — " + notable.prefix(4).joined(separator: ", ")))
            }
        }
        let logic = result.changes.filter { $0.kind == .logic }.count
        if logic > 0 && intent.operation != .logic { highlights.append("\(logic) interactive flow\(logic == 1 ? "" : "s") wired (navigation, forms, list updates)") }
        let vars = result.changes.filter { $0.kind == .variable && $0.summary.hasPrefix("Created") }.count
        if vars > 0 { highlights.append("\(vars) variable\(vars == 1 ? "" : "s") for live data — see the Data panel") }
        if !result.warnings.isEmpty && intent.operation != .createApp { highlights.append("Skipped \(result.warnings.count) unsupported detail\(result.warnings.count == 1 ? "" : "s")") }

        let closing = intent.operation == .createApp || intent.operation == .createScreen
            ? "Tap ▶︎ Preview to try it, drag anything to rearrange it, or tell me what to change."
            : "Anything else you'd like to adjust?"
        return Summary(text: opening + "\n\n" + closing, highlights: highlights, suggestions: suggestions(intent: intent, project: p))
    }

    static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    static func notableProse(_ n: Node) -> String? {
        switch n.type {
        case .statCard: return "KPI cards"
        case .chart: return "a \(n.string("kind")) chart"
        case .list: return n.repeatSource != nil ? "a live list" : "a list"
        case .form: return "a form"
        case .map: return "a map"
        case .gauge: return "a progress gauge"
        case .pager: return "swipeable pages"
        case .grid: return n.repeatSource != nil ? "a product grid" : nil
        case .textField, .secureField: return "input fields"
        case .toggle: return "toggles"
        case .timer: return "a timer"
        case .video: return "a video player"
        case .audio: return "an audio player"
        case .datePicker: return "a date picker"
        case .signInApple: return "Sign in with Apple"
        case .searchField: return "search"
        case .button where n.string("variant") == "prominent": return "the “\(n.string("title"))” action"
        default: return nil
        }
    }

    static func notableName(_ n: Node) -> String? {
        switch n.type {
        case .chart: return "\(n.string("kind")) chart"
        case .statCard: return "KPI cards"
        case .list: return n.repeatSource != nil ? "live list" : "list"
        case .form: return "form"
        case .map: return "map"
        case .gauge: return "gauge"
        case .pager: return "page carousel"
        case .grid: return "grid"
        case .textField, .secureField: return "input fields"
        case .toggle: return "toggles"
        case .timer: return "timer"
        case .video: return "video"
        case .audio: return "audio player"
        case .datePicker: return "date picker"
        case .signInApple: return "Sign in with Apple"
        case .searchField: return "search"
        default: return nil
        }
    }

    static func describeEdits(_ intent: Intent) -> String {
        var parts: [String] = []
        if let c = intent.edits["color"] { parts.append("now \(c)") }
        if let b = intent.edits["bg"] { parts.append("\(b) background") }
        if let s = intent.edits["size"] { parts.append(["bigger", "large", "huge"].contains(s) ? "larger" : (["smaller", "small", "tiny"].contains(s) ? "smaller" : s)) }
        if let t = intent.edits["text"] { parts.append("text “\(t)”") }
        if intent.editFlags.contains("bold") { parts.append("bold") }
        if intent.editFlags.contains("center") { parts.append("centered") }
        if intent.editFlags.contains("full") { parts.append("full width") }
        if intent.edits["radius"] != nil { parts.append("rounded corners") }
        if let s = intent.edits["style"] { parts.append("\(s) style") }
        return listJoin(parts)
    }

    static func suggestions(intent: Intent, project: Project) -> [String] {
        var s: [String] = []
        let names = Set(project.screens.map { $0.name.lowercased() })
        switch intent.archetypes.first ?? (intent.operation == .createApp ? .dashboard : nil) {
        case .dashboard?: s = ["Make the chart a line chart", "Add a budget progress gauge", "Add a dark mode toggle in Settings"]
        case .login?: s = ["Add an onboarding flow before login", "Make the sign-in button red", "Add Face ID sign in"]
        case .settings?: s = ["Add a profile screen", "Add a language picker", "Change the theme to dark with a purple accent"]
        case .store?, .product?: s = ["Add a checkout screen", "Add a search bar", "Add product ratings"]
        case .todo?: s = ["Add due dates to tasks", "Add a progress gauge", "Add a notes screen"]
        default: s = ["Add a settings screen", "Change the theme colors", "Add a login screen"]
        }
        if !names.contains("settings") && !s.contains(where: { $0.contains("settings") }) { s.append("Add a settings screen") }
        return Array(s.prefix(3))
    }

    static func article(_ word: String) -> String {
        guard let f = word.lowercased().first else { return "a" }
        return "aeiou".contains(f) ? "an" : "a"
    }

    public static func listJoin(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }
}
