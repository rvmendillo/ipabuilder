import XCTest
@testable import ReyForgeCore

final class RFSParserTests: XCTestCase {
    func testLineParsing() {
        let l = RFSParser.parseLine("  BUTTON \"Save\" icon=checkmark style=prominent full -> inc count; toast \"Saved\"")!
        XCTAssertEqual(l.kind, .component("BUTTON"))
        XCTAssertEqual(l.indent, 1)
        XCTAssertEqual(l.positional, ["Save"])
        XCTAssertEqual(l.attributes["icon"], "checkmark")
        XCTAssertEqual(l.attributes["style"], "prominent")
        XCTAssertEqual(l.flags, ["full"])
        XCTAssertEqual(l.actions, "inc count; toast \"Saved\"")
        XCTAssertEqual(RFSParser.splitActions(l.actions!), ["inc count", "toast \"Saved\""])
    }

    func testQuotedAttributesAndJSON() {
        let l = RFSParser.parseLine("ROW \"Coffee\" subtitle=\"Today, 9:41\" value=\"-$4.50\" data=[1,2, 3]")!
        XCTAssertEqual(l.attributes["subtitle"], "Today, 9:41")
        XCTAssertEqual(l.attributes["value"], "-$4.50")
        XCTAssertEqual(l.attributes["data"], "[1,2, 3]")
        let v = RFSParser.parseLine("VAR todos list [\"Buy milk\", \"Walk dog\"]")!
        XCTAssertEqual(v.kind, .variable)
        XCTAssertEqual(v.tokens, ["todos", "list", "[\"Buy milk\", \"Walk dog\"]"])
    }

    func testIfBlocks() {
        let a = RFSParser.parseAction("if count > 3 { toast \"Big\"; haptic success } else { back }")!
        XCTAssertEqual(a.verb, "if")
        XCTAssertEqual(a.args, ["count", ">", "3"])
        XCTAssertEqual(a.block?.trimmingCharacters(in: .whitespaces), "toast \"Big\"; haptic success")
        XCTAssertEqual(a.elseBlock?.trimmingCharacters(in: .whitespaces), "back")
    }

    func testCodeFencesAndBulletsAreIgnored() {
        let lines = RFSParser.parse("```\n- TITLE \"Hi\"\n# comment\nTEXT \"Body\"\nEND\nTEXT \"after end\"\n```")
        XCTAssertEqual(lines.count, 2)
    }
}

final class RFSCompilerTests: XCTestCase {
    func types(_ p: Project, screen: String) -> [ComponentType] {
        p.screen(named: screen)!.root.flattened.dropFirst().map { $0.type }
    }

    func testCompilesRealModelOutput() {
        // Verbatim output from Qwen3.5-2B during evaluation (invented symbols, unknown keys, stray lines).
        let script = """
        SCREEN "Dashboard" icon=figure.money
          TITLE "Welcome back, Alex"
          CAPTION "Your spending is on track this week"
          HSTACK
            STAT "Total Balance" "4,250.00" icon=chart.bar
            STAT "Avg. Spend" "12.5%" icon=sf.symbol
          GAUGE "Monthly goal" value=80 max=100
          CHART bar "Mon:30,Tue:45,Wed:15,Thu:60,Fri:25,Sat:10,Sun:5"
          HEADING "Recent Transactions"
          LIST
            ROW "Grocery Store" subtitle="Today" value="-85.00" icon=shopping.bag
            ROW "Netflix Subscription" subtitle="Yesterday" value="-14.99" icon=sf.symbol
            ROW "Coffee Shop" subtitle="2 days ago" value="+12.50" icon=coffee.cup
          BUTTON "Add Transaction" icon=add.circle style=prominent full -> go "Transaction"
          SCROLL "View all history" value=0.6 min=0 max=10
          SPACER spacing=20 theme=dark accent=#333333
        """
        let r = RFSCompiler.compile(script, into: Project(name: "Finance"))
        let p = r.project
        let dash = p.screen(named: "Dashboard")!
        XCTAssertEqual(dash.icon, "dollarsign.circle.fill", "invented symbol mapped to a real one")
        let all = dash.root.flattened
        XCTAssertTrue(all.contains { $0.type == .chart && $0.string("kind") == "bar" })
        let rows = all.filter { $0.type == .listRow }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].string("icon"), "bag.fill")
        XCTAssertEqual(rows[2].string("icon"), "cup.and.saucer.fill")
        XCTAssertTrue(rows.allSatisfy { SymbolResolver.known.contains($0.string("icon")) })
        let button = all.first { $0.type == .button }!
        XCTAssertEqual(button.string("icon"), "plus.circle.fill")
        XCTAssertEqual(button.handlers(for: .tap).first?.kind, .navigate)
        XCTAssertNotNil(p.screen(named: "Transaction"), "navigation target was created so the link works")
        XCTAssertFalse(all.contains { $0.type == .scroll }, "empty scroll container removed")
        XCTAssertTrue(ProjectValidator.errors(p).isEmpty, "\(ProjectValidator.errors(p))")
        XCTAssertFalse(r.warnings.isEmpty, "unknown attributes are reported")
    }

    func testSettingsScreenWithBindings() {
        let script = """
        SCREEN "Settings" icon=gearshape tab
          FORM
            SECTION "Preferences"
              TOGGLE "Notifications" bind=notifications
              TOGGLE "Dark mode" bind=darkMode off
              TOGGLE "Face ID"
              PICKER "Units" "Metric,Imperial" bind=units
            SECTION "Account"
              NAVLINK "Profile" "Profile" icon=person.circle
              BUTTON "Sign out" style=destructive -> confirm "Sign out?" "You can sign back in anytime" { root "Login" }
        """
        let p = RFSCompiler.compile(script, into: Project(name: "App")).project
        XCTAssertEqual(p.variable(named: "notifications")?.type, .bool)
        XCTAssertEqual(p.variable(named: "darkMode")?.initial, false)
        XCTAssertEqual(p.variable(named: "faceID")?.type, .bool, "inputs are auto-bound")
        XCTAssertEqual(p.variable(named: "units")?.initial, "Metric")
        XCTAssertTrue(p.isTab(p.screen(named: "Settings")!.id))
        XCTAssertEqual(p.navigation.style, .tabs)
        let form = p.screen(named: "Settings")!.root.children[0]
        XCTAssertEqual(form.type, .form)
        XCTAssertEqual(form.children.count, 2)
        XCTAssertEqual(form.children[0].children.count, 4)
        let signOut = form.children[1].children[1]
        XCTAssertEqual(signOut.string("variant"), "destructive")
        let confirm = signOut.handlers(for: .tap)[0]
        XCTAssertEqual(confirm.kind, .confirm)
        XCTAssertEqual(confirm.then.first?.kind, .navigate)
        XCTAssertEqual(confirm.then.first?.string("style"), "replace")
        XCTAssertNotNil(p.screen(named: "Login"))
        XCTAssertNotNil(p.screen(named: "Profile"))
    }

    func testCounterLogicRunsEndToEnd() async {
        let script = """
        VAR count number 0
        TEXT "Taps: {{count}}" style=title
        BUTTON "Tap me" icon=hand.tap -> inc count; if count >= 3 { toast "Three taps!" }
        """
        let p = RFSCompiler.compile(script, into: Project(name: "Counter")).project
        let button = p.screens[0].root.flattened.first { $0.type == .button }!
        let state = StateStore(variables: p.variables)
        let host = MockHost()
        let runner = ActionRunner(project: p, state: state, http: MockHTTP(), host: host)
        for _ in 0..<3 { await runner.run(button.handlers(for: .tap)) }
        XCTAssertEqual(state.value("count"), 3)
        XCTAssertEqual(host.events.last, "toast:success:Three taps!")
        let text = p.screens[0].root.flattened.first { $0.type == .text }!
        XCTAssertEqual(Template.render(text.string("text"), scope: Scope(globals: state)), "Taps: 3")
    }

    func testTodoListWithRepeat() {
        let script = """
        SCREEN "Tasks" icon=checklist
          FIELD "New task" bind=newTask
          BUTTON "Add" icon=plus -> add todos newTask; set newTask = ""
          LIST source=todos
        """
        let p = RFSCompiler.compile(script, into: Project(name: "Todo")).project
        XCTAssertEqual(p.variable(named: "todos")?.type, .list)
        let list = p.screen(named: "Tasks")!.root.flattened.first { $0.type == .list }!
        XCTAssertEqual(list.repeatSource, "todos")
        XCTAssertEqual(list.children.count, 1, "row template generated")
        let add = p.screen(named: "Tasks")!.root.flattened.first { $0.type == .button }!.handlers(for: .tap)
        XCTAssertEqual(add[0].kind, .appendItem)
        XCTAssertEqual(add[0].string("item"), "{{newTask}}")
        XCTAssertEqual(add[1].kind, .setVariable)
    }

    func testEditSelectedAndDelete() {
        var p = Project(name: "Demo")
        let button = Node(type: .button, props: ["title": "Continue", "size": "regular"])
        let text = Node(type: .text, props: ["text": "Welcome"])
        var s = Screen(name: "Home")
        s.root.children = [text, button]
        p.addScreen(s)
        let ctx = EditorContext(screenID: s.id, selectedNodeID: button.id)
        var r = RFSCompiler.compile("EDIT selected color=red size=bigger", into: p, context: ctx)
        let edited = r.project.node(id: button.id)!
        XCTAssertEqual(edited.string("tint"), "red")
        XCTAssertEqual(edited.string("size"), "large")
        XCTAssertEqual(r.changes.first?.kind, .updatedNode)
        r = RFSCompiler.compile("EDIT \"Welcome\" text=\"Hello again\" bold", into: r.project, context: ctx)
        XCTAssertEqual(r.project.node(id: text.id)!.string("text"), "Hello again")
        XCTAssertEqual(r.project.node(id: text.id)!.style.font?.weight, "bold")
        r = RFSCompiler.compile("EDIT button \"Continue\" -> go \"Details\"", into: r.project, context: EditorContext(screenID: s.id))
        XCTAssertEqual(r.project.node(id: button.id)!.handlers(for: .tap).first?.kind, .navigate)
        r = RFSCompiler.compile("DELETE selected", into: r.project, context: EditorContext(screenID: s.id, selectedNodeID: text.id))
        XCTAssertNil(r.project.node(id: text.id))
        XCTAssertNotNil(r.project.node(id: button.id))
    }

    func testAddsAfterSelectionWithoutScreenLine() {
        var p = Project(name: "Demo")
        let a = Node(type: .text, props: ["text": "A"])
        let b = Node(type: .text, props: ["text": "B"])
        var s = Screen(name: "Home")
        s.root.children = [a, b]
        p.addScreen(s)
        let r = RFSCompiler.compile("BUTTON \"One\"\nBUTTON \"Two\"", into: p, context: EditorContext(screenID: s.id, selectedNodeID: a.id))
        let titles = r.project.screens[0].root.children.map { $0.string("text").isEmpty ? $0.string("title") : $0.string("text") }
        XCTAssertEqual(titles, ["A", "One", "Two", "B"])
    }

    func testThemeAndBrand() {
        let r = RFSCompiler.compile("APP name=\"Brew\" accent=#8B5E3C theme=dark font=serif icon=coffee", into: Project(name: "x"))
        XCTAssertEqual(r.project.brand.displayName, "Brew")
        XCTAssertEqual(r.project.theme.accent, "#8B5E3C")
        XCTAssertEqual(r.project.theme.appearance, .dark)
        XCTAssertEqual(r.project.theme.fontDesign, "serif")
        XCTAssertEqual(r.project.brand.icon.symbol, "cup.and.saucer.fill")
        let preset = RFSCompiler.compile("APP preset=sunset", into: Project(name: "x")).project
        XCTAssertEqual(preset.theme.accent, "#FF5E3A")
    }

    func testAPIAction() {
        let r = RFSCompiler.compile("BUTTON \"Refresh\" -> get \"https://api.open-meteo.com/v1/forecast?latitude=14.6&longitude=121&current=temperature_2m\" into temperature \"current.temperature_2m\"", into: Project(name: "W"))
        let a = r.project.screens[0].root.children[0].handlers(for: .tap)[0]
        XCTAssertEqual(a.kind, .apiRequest)
        XCTAssertEqual(a.string("resultVariable"), "temperature")
        XCTAssertEqual(a.string("resultPath"), "current.temperature_2m")
    }

    func testFreeLayoutChildrenGetPositions() {
        let r = RFSCompiler.compile("ZSTACK height=300\n  CIRCLE color=orange\n  TEXT \"Badge\" x=120 y=40", into: Project(name: "Z"))
        let z = r.project.screens[0].root.children[0]
        XCTAssertEqual(z.type, .zstack)
        XCTAssertNotNil(z.children[0].style.offsetX)
        XCTAssertEqual(z.children[1].style.offsetX, 120)
    }

    func testSymbolResolver() {
        XCTAssertEqual(SymbolResolver.resolve("star.fill"), "star.fill")
        XCTAssertEqual(SymbolResolver.resolve("map-pin"), "mappin.and.ellipse")
        XCTAssertEqual(SymbolResolver.resolve("users"), "person.2.fill")
        XCTAssertEqual(SymbolResolver.resolve("dollar.sign.circle"), "dollarsign.circle.fill")
        XCTAssertEqual(SymbolResolver.resolve("shopping-cart"), "cart.fill")
        XCTAssertEqual(SymbolResolver.resolve("totally.unknown.thing"), "circle.fill")
        XCTAssertEqual(SymbolResolver.symbol(forConcept: "Monthly spending"), "creditcard.fill")
        for (_, target) in SymbolResolver.synonyms {
            XCTAssertTrue(SymbolResolver.known.contains(target), "synonym target \(target) must be a known symbol")
        }
    }
}

final class ProjectOpsTests: XCTestCase {
    func makeProject() -> (Project, [String]) {
        var p = Project(name: "Ops")
        let a = Node(type: .text, props: ["text": "A"])
        let b = Node(type: .text, props: ["text": "B"])
        var card = Node(type: .card)
        let c = Node(type: .text, props: ["text": "C"])
        card.children = [c]
        var s = Screen(name: "Home")
        s.root.children = [a, card, b]
        p.addScreen(s)
        return (p, [a.id, card.id, b.id, c.id])
    }

    func testMoveIntoContainerAndReorder() {
        var (p, ids) = makeProject()
        XCTAssertTrue(p.move(ids[0], to: ids[1], at: 1))
        XCTAssertEqual(p.node(id: ids[1])!.children.map { $0.string("text") }, ["C", "A"])
        let root = p.screens[0].root.id
        XCTAssertTrue(p.move(ids[2], to: root, at: 0))
        XCTAssertEqual(p.screens[0].root.children.map { $0.id }, [ids[2], ids[1]])
        // Moving forward within the same parent accounts for the removed slot.
        XCTAssertTrue(p.move(ids[2], to: root, at: 2))
        XCTAssertEqual(p.screens[0].root.children.map { $0.id }, [ids[1], ids[2]])
        XCTAssertFalse(p.move(ids[1], to: ids[3], at: 0), "cannot move into a leaf")
        XCTAssertFalse(p.move(ids[1], to: ids[1], at: 0), "cannot move into itself")
    }

    func testDuplicateWrapUnwrapRemove() {
        var (p, ids) = makeProject()
        let dup = p.duplicateNode(ids[1])!
        XCTAssertNotEqual(dup, ids[1])
        XCTAssertEqual(p.screens[0].root.children.count, 4)
        XCTAssertNotEqual(p.node(id: dup)!.children[0].id, ids[3], "children get fresh ids")
        let wrapper = p.wrap(ids[0], in: .hstack)!
        XCTAssertEqual(p.node(id: wrapper)!.children[0].id, ids[0])
        XCTAssertTrue(p.unwrap(wrapper))
        XCTAssertNil(p.node(id: wrapper))
        XCTAssertNotNil(p.removeNode(ids[0]))
        XCTAssertNil(p.node(id: ids[0]))
        XCTAssertTrue(p.moveWithinParent(ids[2], by: -1))
    }

    func testRenameVariableUpdatesReferences() {
        var p = Project(name: "Vars")
        p.variables = [Variable(name: "count", type: .number)]
        var s = Screen(name: "Home")
        var button = Node(type: .button, props: ["title": "{{count}} taps"])
        button.events = [EventHandler(event: .tap, actions: [.increment("count"), .when("count > 2", then: [.set("count", "count - 1")])])]
        s.root.children = [button, Node(type: .stepper, binding: "count")]
        p.addScreen(s)
        p.renameVariable("count", to: "taps")
        let b = p.screens[0].root.children[0]
        XCTAssertEqual(b.string("title"), "{{taps}} taps")
        XCTAssertEqual(b.events[0].actions[0].string("variable"), "taps")
        XCTAssertEqual(b.events[0].actions[1].string("condition"), "taps > 2")
        XCTAssertEqual(b.events[0].actions[1].then[0].string("value"), "taps - 1")
        XCTAssertEqual(p.screens[0].root.children[1].binding, "taps")
    }

    func testCodableRoundTripAndNormalize() throws {
        var (p, _) = makeProject()
        p.variables.append(Variable(name: "dup", type: .text))
        p.variables.append(Variable(name: "dup", type: .number))
        let data = try p.jsonData()
        let back = try Project.decode(data)
        XCTAssertEqual(back.variables.count, 1, "duplicates removed on normalize")
        XCTAssertEqual(back.screens[0].root.flattened.count, p.screens[0].root.flattened.count)
        // Partial JSON (as an AI or older build might write) still decodes.
        let partial = try Project.decode(Data("{\"name\":\"Tiny\",\"screens\":[{\"name\":\"Only\",\"root\":{\"type\":\"vstack\",\"children\":[{\"type\":\"kpi\",\"props\":{\"title\":\"X\"}}]}}]}".utf8))
        XCTAssertEqual(partial.screens[0].root.children[0].type, .statCard)
        XCTAssertEqual(partial.navigation.initialScreenID, partial.screens[0].id)
    }

    func testBundleIDs() {
        XCTAssertEqual(BundleID.suggest(for: "My Café App!"), "com.reyforge.mycafeapp")
        XCTAssertTrue(BundleID.isValid("com.rvmendillo.reyforge"))
        XCTAssertFalse(BundleID.isValid("com..x"))
        XCTAssertFalse(BundleID.isValid("single"))
        XCTAssertTrue(BundleID.matches(pattern: "ABCDE12345.*", bundleID: "com.any.thing"))
        XCTAssertTrue(BundleID.matches(pattern: "ABCDE12345.com.foo.*", bundleID: "com.foo.bar"))
        XCTAssertFalse(BundleID.matches(pattern: "ABCDE12345.com.foo.bar", bundleID: "com.foo.baz"))
        XCTAssertTrue(BundleID.matches(pattern: "ABCDE12345.com.foo.bar", bundleID: "com.foo.bar"))
    }

    func testValidatorFindsProblems() {
        var p = Project(name: "Bad", bundleID: "bad")
        var s = Screen(name: "Home")
        var b = Node(type: .button)
        b.events = [EventHandler(event: .tap, actions: [.navigate("Nowhere"), .increment("ghost")])]
        s.root.children = [b, Node(type: .toggle, binding: "missing")]
        p.addScreen(s)
        let issues = ProjectValidator.validate(p)
        XCTAssertTrue(issues.contains { $0.message.contains("Bundle identifier") })
        XCTAssertTrue(issues.contains { $0.message.contains("missing screen") })
        XCTAssertTrue(issues.contains { $0.message.contains("ghost") })
        XCTAssertTrue(issues.contains { $0.message.contains("missing") && $0.severity == .warning })
    }

    func testLegacyMigration() {
        let json = """
        [{"id":"7E5C2A5C-4D7A-4C4E-9E86-3D5F0B9B1A11","name":"Old App","bundleIdentifier":"com.rvmendillo.old",
          "variables":{"count":0,"greeting":"Hi"},
          "components":[
            {"kind":"text","text":"Hello","x":195,"y":120,"width":300,"height":40,"fontSize":28},
            {"kind":"button","text":"Tap","x":195,"y":300,"width":200,"height":50,"actions":[{"kind":"increment","key":"count","value":""},{"kind":"showAlert","key":"Hi","value":"There"}]},
            {"kind":"toggle","text":"Wi-Fi","x":195,"y":380,"width":300,"height":44},
            {"kind":"navigationLink","text":"More","detail":"Details","x":195,"y":440,"width":300,"height":44}
          ],
          "widget":{"enabled":true,"displayName":"Old","family":"systemMedium"}}]
        """
        let projects = LegacyMigration.migrate(data: Data(json.utf8))
        XCTAssertEqual(projects.count, 1)
        let p = projects[0]
        XCTAssertEqual(p.bundleID, "com.rvmendillo.old")
        XCTAssertEqual(p.id.uuidString, "7E5C2A5C-4D7A-4C4E-9E86-3D5F0B9B1A11")
        let canvas = p.screens[0].root.children[0]
        XCTAssertEqual(canvas.type, .zstack)
        XCTAssertEqual(canvas.children.count, 4)
        XCTAssertEqual(canvas.children[0].style.offsetX, 45)
        XCTAssertEqual(canvas.children[0].style.offsetY, 100)
        XCTAssertEqual(canvas.children[1].handlers(for: .tap).map { $0.kind }, [.increment, .alert])
        XCTAssertNotNil(p.screen(named: "Details"))
        XCTAssertEqual(p.widget.family, .medium)
        XCTAssertTrue(ProjectValidator.errors(p).isEmpty, "\(ProjectValidator.errors(p))")
    }
}
