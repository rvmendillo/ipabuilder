import XCTest
@testable import ReyForgeCore

final class RecipeSweepTests: XCTestCase {
    /// Every archetype for every domain must compile into a valid, fully linked project.
    func testAllRecipesCompileForAllDomains() {
        var warningsSeen = Set<String>()
        for domain in Domain.allCases {
            let pack = ContentPacks.pack(domain)
            for a in Archetype.allCases {
                let script = Recipes.screen(a, pack: pack, options: RecipeOptions(screenName: a.defaultName, tab: true, appName: pack.appName))
                let r = RFSCompiler.compile(script, into: Project(name: pack.appName))
                XCTAssertFalse(r.isEmpty, "\(a) / \(domain) produced nothing")
                let errors = ProjectValidator.errors(r.project)
                XCTAssertTrue(errors.isEmpty, "\(a) / \(domain): \(errors)")
                let issues = ProjectValidator.validate(r.project).filter { $0.severity == .warning }
                XCTAssertTrue(issues.isEmpty, "\(a) / \(domain) warnings: \(issues)")
                for w in r.warnings { warningsSeen.insert("\(a): \(w)") }
                let screen = r.project.screen(named: a.defaultName)
                XCTAssertNotNil(screen, "\(a) screen missing")
                XCTAssertGreaterThan(screen?.root.flattened.count ?? 0, 2, "\(a) screen is empty")
            }
        }
        XCTAssertTrue(warningsSeen.isEmpty, "Recipes use unsupported syntax:\n" + warningsSeen.sorted().joined(separator: "\n"))
    }

    func testAllAppBlueprintsCompile() {
        for domain in Domain.allCases {
            let script = Recipes.app(pack: ContentPacks.pack(domain), includeLogin: true, includeOnboarding: true)
            let r = RFSCompiler.compile(script, into: Project(name: "x"))
            XCTAssertTrue(ProjectValidator.errors(r.project).isEmpty, "\(domain): \(ProjectValidator.errors(r.project))")
            XCTAssertGreaterThanOrEqual(r.project.navigation.tabs.count, 3, "\(domain) tabs")
            XCTAssertEqual(r.project.navigation.style, .tabs)
            XCTAssertEqual(r.project.brand.displayName, ContentPacks.pack(domain).appName)
            XCTAssertTrue(r.warnings.isEmpty, "\(domain): \(r.warnings)")
        }
    }
}

final class AgentTests: XCTestCase {
    let agent = VibeAgent()

    override func setUp() { ExpressionEngine.locale = Locale(identifier: "en_US") }

    func run(_ message: String, project: Project = Project(name: "Untitled"), context: EditorContext = EditorContext()) async -> AgentResult {
        await agent.respond(to: message, project: project, context: context)
    }

    func nodes(_ r: AgentResult, screen: String) -> [Node] { r.project?.screen(named: screen)?.root.flattened ?? [] }

    func assertValid(_ r: AgentResult, file: StaticString = #filePath, line: UInt = #line) {
        guard let p = r.project else { return XCTFail("no project change: \(r.reply)", file: file, line: line) }
        XCTAssertTrue(ProjectValidator.errors(p).isEmpty, "\(ProjectValidator.errors(p))", file: file, line: line)
    }

    func testFinanceDashboard() async {
        let r = await run("Create a dashboard for a personal finance app with KPIs, a spending chart, recent transactions and an add button")
        XCTAssertEqual(r.intent.operation, .createScreen)
        XCTAssertEqual(r.intent.domain, .finance)
        assertValid(r)
        let n = nodes(r, screen: "Dashboard")
        XCTAssertGreaterThanOrEqual(n.filter { $0.type == .statCard }.count, 4)
        XCTAssertTrue(n.contains { $0.type == .chart })
        XCTAssertTrue(n.contains { $0.type == .list && $0.repeatSource == "transactions" })
        let add = n.first { $0.type == .button && $0.string("title").lowercased().contains("add") }!
        XCTAssertEqual(add.handlers(for: .tap).first?.string("style"), "sheet")
        let form = nodes(r, screen: "New Transaction")
        XCTAssertGreaterThanOrEqual(form.filter { $0.type == .textField }.count, 2)
        XCTAssertTrue(r.reply.contains("Dashboard"))
        XCTAssertFalse(r.highlights.isEmpty)
        XCTAssertEqual(r.suggestions.count, 3)
    }

    func testSettingsWithToggles() async {
        let r = await run("make a settings screen with notifications, dark mode and face id toggles")
        XCTAssertEqual(r.intent.operation, .createScreen)
        assertValid(r)
        let toggles = nodes(r, screen: "Settings").filter { $0.type == .toggle }.map { $0.string("title").lowercased() }
        XCTAssertTrue(toggles.contains { $0.contains("notification") })
        XCTAssertTrue(toggles.contains { $0.contains("dark") })
        XCTAssertTrue(toggles.contains { $0.contains("face id") })
    }

    func testStoreCreatesShoppingFlow() async {
        let r = await run("build an online store home page with product grid")
        XCTAssertEqual(r.intent.operation, .createScreen)
        assertValid(r)
        let p = r.project!
        XCTAssertTrue(nodes(r, screen: "Shop").contains { $0.type == .grid && $0.repeatSource != nil })
        XCTAssertNotNil(p.screen(named: "Product"))
        XCTAssertNotNil(p.screen(named: "Cart"))
        XCTAssertNotNil(p.screen(named: "Checkout"))
    }

    func testWholeAppFromOneSentence() async {
        let r = await run("Build me a fitness tracker app")
        XCTAssertEqual(r.intent.operation, .createApp)
        XCTAssertEqual(r.intent.domain, .fitness)
        assertValid(r)
        let p = r.project!
        XCTAssertEqual(p.navigation.style, .tabs)
        XCTAssertEqual(p.navigation.tabs.map { $0.title }, ["Today", "Workout", "History", "Profile"])
        XCTAssertEqual(p.brand.displayName, "Stride")
        XCTAssertTrue(r.reply.contains("Stride"))
    }

    func testUnknownTopicApp() async {
        let r = await run("Create a beekeeping app")
        XCTAssertEqual(r.intent.operation, .createApp)
        XCTAssertEqual(r.intent.topic, "beekeeping")
        assertValid(r)
        XCTAssertEqual(r.project!.brand.displayName, "Beekeeping")
        XCTAssertEqual(r.project!.brand.icon.symbol, "hexagon.fill")
    }

    func testTodoWhereICanAddTasks() async {
        let r = await run("add a todo list where I can add tasks", project: projectWithHome())
        XCTAssertEqual(r.intent.operation, .createScreen)
        assertValid(r)
        let n = nodes(r, screen: "Tasks")
        XCTAssertTrue(n.contains { $0.type == .list && $0.repeatSource == "todos" })
        XCTAssertTrue(n.contains { $0.type == .textField })
    }

    func testEditSelection() async {
        var p = projectWithHome()
        let button = Node(type: .button, props: ["title": "Continue", "size": "regular"])
        p.screens[0].root.children.append(button)
        let r = await run("make this button red and bigger", project: p, context: EditorContext(screenID: p.screens[0].id, selectedNodeID: button.id))
        XCTAssertEqual(r.intent.operation, .edit)
        let edited = r.project!.node(id: button.id)!
        XCTAssertEqual(edited.string("tint"), "red")
        XCTAssertEqual(edited.string("size"), "large")
        XCTAssertTrue(r.reply.contains("Continue"), r.reply)
    }

    func testEditByDescriptionWithoutSelection() async {
        var p = projectWithHome()
        let title = Node(type: .text, props: ["text": "Welcome"], style: Style(font: FontSpec(style: "title")))
        p.screens[0].root.children.insert(title, at: 0)
        let r = await run("make the title bold and blue", project: p, context: EditorContext(screenID: p.screens[0].id))
        XCTAssertEqual(r.intent.operation, .edit)
        let edited = r.project!.node(id: title.id)!
        XCTAssertEqual(edited.style.foreground, "blue")
        XCTAssertEqual(edited.style.font?.weight, "bold")
    }

    func testTheme() async {
        let r = await run("change the theme to dark with a purple accent", project: projectWithHome())
        XCTAssertEqual(r.intent.operation, .theme)
        XCTAssertEqual(r.project!.theme.appearance, .dark)
        XCTAssertEqual(r.project!.theme.accent, "#AF52DE")
        let r2 = await run("give the app a luxury look", project: projectWithHome())
        XCTAssertEqual(r2.project?.theme.presetID, "luxury")
        let r3 = await run("rename the app to Brew", project: projectWithHome())
        XCTAssertEqual(r3.project?.brand.displayName, "Brew")
    }

    func testOnboarding() async {
        let r = await run("onboarding with 3 pages and a get started button")
        XCTAssertEqual(r.intent.operation, .createScreen)
        assertValid(r)
        let pager = nodes(r, screen: "Welcome").first { $0.type == .pager }!
        XCTAssertEqual(pager.children.count, 3)
    }

    func testLogicNavigation() async {
        var p = projectWithHome()
        let button = Node(type: .button, props: ["title": "Continue"])
        p.screens[0].root.children.append(button)
        p.addScreen(Screen(name: "Details"))
        let r = await run("when I tap the Continue button go to the Details screen", project: p, context: EditorContext(screenID: p.screens[0].id))
        XCTAssertEqual(r.intent.operation, .logic)
        let a = r.project!.node(id: button.id)!.handlers(for: .tap)
        XCTAssertEqual(a.first?.kind, .navigate)
        XCTAssertEqual(a.first?.string("screen"), r.project!.screen(named: "Details")!.id)
        XCTAssertEqual(r.project!.screens.count, 2, "no duplicate Details screen")
    }

    func testLogicAlertOnSelection() async {
        var p = projectWithHome()
        let button = Node(type: .button, props: ["title": "Save"])
        p.screens[0].root.children.append(button)
        let r = await run("make it show an alert saying \"Saved!\" when tapped", project: p, context: EditorContext(screenID: p.screens[0].id, selectedNodeID: button.id))
        XCTAssertEqual(r.intent.operation, .logic)
        let a = r.project!.node(id: button.id)!.handlers(for: .tap)
        XCTAssertEqual(a.first?.kind, .alert)
        XCTAssertEqual(a.first?.string("title"), "Saved!")
    }

    func testBookingWithMap() async {
        let r = await run("restaurant booking screen with date picker, guests and a map")
        XCTAssertEqual(r.intent.operation, .createScreen)
        assertValid(r)
        let n = nodes(r, screen: "Book")
        XCTAssertTrue(n.contains { $0.type == .datePicker })
        XCTAssertTrue(n.contains { $0.type == .stepper })
        XCTAssertTrue(n.contains { $0.type == .map })
    }

    func testWeatherAppUsesLiveAPI() async {
        let r = await run("weather app")
        XCTAssertEqual(r.intent.operation, .createApp)
        assertValid(r)
        let screen = r.project!.screen(named: "Weather")!
        XCTAssertEqual(screen.onAppear.first?.kind, .apiRequest)
        XCTAssertTrue(screen.onAppear.first!.string("url").contains("open-meteo"))
        XCTAssertEqual(screen.refreshActions.first?.kind, .apiRequest)
    }

    func testMusicPlayerAndChat() async {
        let r = await run("music player screen")
        XCTAssertEqual(r.intent.archetypes.first, .player)
        XCTAssertTrue(nodes(r, screen: "Now Playing").contains { $0.type == .audio })
        let c = await run("a chat messages screen")
        assertValid(c)
        XCTAssertNotNil(c.project?.screen(named: "Messages") ?? c.project?.screen(named: "Chat"))
    }

    func testDeleteSelection() async {
        var p = projectWithHome()
        let t = Node(type: .text, props: ["text": "Welcome"])
        p.screens[0].root.children.append(t)
        let r = await run("delete this", project: p, context: EditorContext(screenID: p.screens[0].id, selectedNodeID: t.id))
        XCTAssertEqual(r.intent.operation, .delete)
        XCTAssertNil(r.project!.node(id: t.id))
        XCTAssertTrue(r.reply.contains("Removed"))
    }

    func testAddSpecificElements() async {
        let home = projectWithHome()
        let ctx = EditorContext(screenID: home.screens[0].id)
        let r = await run("add a red button that says \"Buy now\"", project: home, context: ctx)
        XCTAssertEqual(r.intent.operation, .addElements)
        let b = nodes(r, screen: "Home").first { $0.type == .button }!
        XCTAssertEqual(b.string("title"), "Buy now")
        XCTAssertEqual(b.string("tint"), "red")
        let r2 = await run("add a toggle for notifications and a slider for volume", project: home, context: ctx)
        let n2 = nodes(r2, screen: "Home")
        XCTAssertEqual(n2.first { $0.type == .toggle }?.string("title"), "Notifications")
        XCTAssertEqual(n2.first { $0.type == .slider }?.string("title"), "Volume")
        XCTAssertNotNil(r2.project?.variable(named: "volume"))
        let r3 = await run("add a map of Paris", project: home, context: ctx)
        let map = nodes(r3, screen: "Home").first { $0.type == .map }!
        XCTAssertEqual(map.number("latitude")!, 48.8566, accuracy: 0.001)
        let r4 = await run("add a line chart of weekly sales", project: home, context: ctx)
        XCTAssertEqual(nodes(r4, screen: "Home").first { $0.type == .chart }?.string("kind"), "line")
        let r5 = await run("add a counter", project: home, context: ctx)
        XCTAssertNotNil(r5.project?.variable(named: "count"))
        XCTAssertEqual(nodes(r5, screen: "Home").filter { $0.type == .button }.count, 3)
    }

    func testQuestionsAndGreetings() async {
        let q = await run("how do I add logic?")
        XCTAssertEqual(q.intent.operation, .question)
        XCTAssertNil(q.project)
        XCTAssertTrue(q.reply.contains("Logic"))
        let h = await run("hi")
        XCTAssertEqual(h.intent.operation, .greeting)
        XCTAssertFalse(h.suggestions.isEmpty)
        let polite = await run("can you make a login screen?")
        XCTAssertEqual(polite.intent.operation, .createScreen)
        XCTAssertNotNil(polite.project?.screen(named: "Login"))
    }

    // MARK: Engines

    func testStrongEngineScriptIsUsed() async {
        let engine = ScriptedEngine(tier: .strong, responses: ["SAY \"I built a minimalist timer.\"\nSCREEN \"Focus\" icon=timer tab\n  TIMER 1500\n  BUTTON \"Start\" -> haptic success"])
        let a = VibeAgent(engine: engine)
        let r = await a.respond(to: "make a focus timer screen", project: Project(name: "x"))
        XCTAssertNotNil(r.project?.screen(named: "Focus"))
        XCTAssertTrue(r.reply.hasPrefix("I built a minimalist timer."))
        XCTAssertTrue(engine.requests[0].system.contains("ReyForge Script"))
        XCTAssertTrue(engine.requests[0].messages.last!.content.contains("Request: make a focus timer screen"))
    }

    func testStrongEngineGarbageFallsBackToDesignEngine() async {
        let a = VibeAgent(engine: ScriptedEngine(tier: .strong, responses: ["Sorry, I can't help with that."]))
        let r = await a.respond(to: "create a login screen", project: Project(name: "x"))
        XCTAssertNotNil(r.project?.screen(named: "Login"))
    }

    func testLocalEngineEnrichesUnknownTopics() async {
        let json = #"{"stats":[{"title":"Hives","value":"12","icon":"hexagon"},{"title":"Honey","value":"48 kg","icon":"drop"},{"title":"Queens","value":"11","icon":"crown"}],"items":[{"title":"Hive A","subtitle":"Checked today","value":"Healthy","icon":"leaf"},{"title":"Hive B","subtitle":"2 days ago","value":"Swarm risk","icon":"bug"},{"title":"Hive C","subtitle":"Mon","value":"Healthy","icon":"leaf"},{"title":"Hive D","subtitle":"Sun","value":"Feed","icon":"drop"}],"chart":{"title":"Honey (kg)","points":[{"label":"Mon","value":3},{"label":"Tue","value":5},{"label":"Wed","value":4},{"label":"Thu","value":6},{"label":"Fri","value":5},{"label":"Sat","value":8},{"label":"Sun","value":7}]}}"#
        let engine = ScriptedEngine(tier: .local, responses: [json])
        let a = VibeAgent(engine: engine)
        let r = await a.respond(to: "create a dashboard for my beekeeping app", project: Project(name: "x"))
        XCTAssertEqual(engine.requests.first?.grammar, Grammars.content)
        let stats = nodes(r, screen: "Dashboard").filter { $0.type == .statCard }.map { $0.string("title") }
        XCTAssertEqual(stats.prefix(3), ["Hives", "Honey", "Queens"])
        XCTAssertTrue(nodes(r, screen: "Dashboard").contains { $0.type == .chart && $0.string("data").contains("Sat:8") })
    }

    func testLocalEngineAnswersQuestions() async {
        let engine = ScriptedEngine(tier: .local, responses: ["Open the Logic tab and add an action."])
        let a = VibeAgent(engine: engine)
        let r = await a.respond(to: "how do I add an action to a button?", project: Project(name: "x"))
        XCTAssertEqual(r.reply, "Open the Logic tab and add an action.")
        XCTAssertTrue(engine.requests[0].system.contains("Relevant ReyForge documentation"))
    }

    func testLocalEngineHandlesFreeFormAdditions() async {
        let engine = ScriptedEngine(tier: .local, responses: ["CARD\n  HEADING \"Top goals\"\n  PROGRESS \"Run a 10K\" value=0.7\n  PROGRESS \"Read 12 books\" value=0.4\nEND"])
        let a = VibeAgent(engine: engine)
        let home = projectWithHome()
        let r = await a.respond(to: "show my top goals with progress bars", project: home, context: EditorContext(screenID: home.screens[0].id))
        XCTAssertEqual(nodes(r, screen: "Home").filter { $0.type == .progress }.count, 2)
        XCTAssertEqual(engine.requests.first?.grammar, Grammars.elements)
    }

    func testClaudeRequestShape() throws {
        let c = ClaudeEngine(apiKey: "sk-test", model: "claude-opus-5-5")
        let req = try c.urlRequest(for: LLMRequest(system: "sys", messages: [LLMMessage(role: "user", content: "hi")]))
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil(body["temperature"], "temperature is rejected by the current API version")
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "adaptive")
        XCTAssertEqual((body["output_config"] as? [String: String])?["effort"], "medium")
        let haiku = ClaudeEngine(apiKey: "k", model: "claude-haiku-5-5")
        let hb = try JSONSerialization.jsonObject(with: try haiku.urlRequest(for: LLMRequest(system: "s", messages: [])).httpBody!) as! [String: Any]
        XCTAssertNil(hb["fallbacks"], "Haiku has no server-side fallback")
    }

    func testSSEParsing() {
        var p = SSEParser()
        var events = p.feed("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel\"}}\n\n")
        events += p.feed("data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}\n")
        events += p.finish()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].event, "content_block_delta")
        XCTAssertTrue(events[1].data.contains("\"lo\""))
    }

    func testOpenAICompatibleRequest() throws {
        let e = OpenAICompatibleEngine(baseURL: URL(string: "http://192.168.1.20:11434")!, model: "qwen3:8b")
        let r = try e.urlRequest(for: LLMRequest(system: "s", messages: [LLMMessage(role: "user", content: "u")]))
        XCTAssertEqual(r.url?.absoluteString, "http://192.168.1.20:11434/v1/chat/completions")
        let body = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
        XCTAssertEqual((body["messages"] as! [[String: String]]).first?["role"], "system")
    }

    func projectWithHome() -> Project {
        var p = Project(name: "Demo")
        var s = Screen(name: "Home", icon: "house.fill")
        s.root.children = [Node(type: .text, props: ["text": "Hello"])]
        p.addScreen(s)
        return p
    }
}

final class AnalyzerTests: XCTestCase {
    func op(_ s: String, selected: Bool = false) -> Intent.Operation {
        RequestAnalyzer.analyze(s, project: nil, context: EditorContext(selectedNodeID: selected ? "n1" : nil)).operation
    }

    func testOperations() {
        XCTAssertEqual(op("Build a coffee shop app with ordering and rewards"), .createApp)
        XCTAssertEqual(op("I want an app for my bakery"), .createApp)
        XCTAssertEqual(op("create a profile page"), .createScreen)
        XCTAssertEqual(op("add a search bar"), .addElements)
        XCTAssertEqual(op("make it green", selected: true), .edit)
        XCTAssertEqual(op("remove the image"), .delete)
        XCTAssertEqual(op("use a sunset theme"), .theme)
        XCTAssertEqual(op("what can you do?"), .question)
        XCTAssertEqual(op("thanks!"), .greeting)
    }

    func testEntityExtraction() {
        let i = RequestAnalyzer.analyze("Create a dashboard for a personal finance app called \"Pennywise\" with 3 stat cards in blue")
        XCTAssertEqual(i.domain, .finance)
        XCTAssertEqual(i.appName, "Pennywise")
        XCTAssertEqual(i.archetypes.first, .dashboard)
        XCTAssertEqual(i.colors, ["blue"])
        XCTAssertEqual(i.components.first { $0.type == .statCard }?.count, 3)
        XCTAssertEqual(RequestAnalyzer.analyze("make an app for my dog walking business").topic, "dog walking")
        XCTAssertEqual(RequestAnalyzer.analyze("make an app for my dog walking business").domain, .pets)
    }
}
