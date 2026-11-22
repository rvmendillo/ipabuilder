import XCTest
@testable import ReyForgeCore

final class ValueTests: XCTestCase {
    func testJSONRoundTrip() throws {
        let v: Value = ["name": "Ana", "age": 31, "tags": ["a", "b"], "ok": true, "none": .null]
        let data = try JSONEncoder().encode(v)
        let back = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(back, v)
        XCTAssertEqual(back["tags"][1], "b")
    }

    func testBoolsStayBools() throws {
        let back = try JSONDecoder().decode(Value.self, from: Data("[true, 1, 0, false]".utf8))
        XCTAssertEqual(back, [true, 1, 0, false])
    }

    func testCoercion() {
        XCTAssertEqual(Value.string("$1,200.50").numberValue, 1200.5)
        XCTAssertEqual(Value.string("45%").numberValue, 0.45)
        XCTAssertEqual(Value.string("-€3").numberValue, -3)
        XCTAssertFalse(Value.string("off").boolValue)
        XCTAssertTrue(Value.string("yes").boolValue)
        XCTAssertEqual(Value.number(12).stringValue, "12")
        XCTAssertEqual(Value.number(12.25).stringValue, "12.25")
        XCTAssertEqual(Value.string("a, b ,c").arrayValue, ["a", "b", "c"])
        XCTAssertEqual(ValueKind.number.coerce("7.5"), 7.5)
        XCTAssertEqual(ValueKind.bool.coerce("true"), true)
    }

    func testPaths() {
        let v: Value = ["current": ["temperature_2m": 21.5], "items": [["title": "x"], ["title": "y"]]]
        XCTAssertEqual(v.value(atPath: "current.temperature_2m"), 21.5)
        XCTAssertEqual(v.value(atPath: "items.1.title"), "y")
        XCTAssertEqual(v.value(atPath: "items[0].title"), "x")
    }

    func testParseLiteral() {
        XCTAssertEqual(Value.parseLiteral("42"), 42)
        XCTAssertEqual(Value.parseLiteral("true"), true)
        XCTAssertEqual(Value.parseLiteral("[1,2]"), [1, 2])
        XCTAssertEqual(Value.parseLiteral("\"hi\""), "hi")
        XCTAssertEqual(Value.parseLiteral("Hello there"), "Hello there")
    }
}

final class ExpressionTests: XCTestCase {
    let lookup = DictionaryLookup([
        "count": 3, "price": "12.5", "qty": 2, "name": "Rey", "isOn": true,
        "cart": [["title": "Tea", "price": 4.5], ["title": "Cake", "price": 6]],
        "user": ["name": "Ana", "address": ["city": "Manila"]],
        "empty": "",
    ])
    var scope: Scope { Scope(globals: lookup) }

    override func setUp() {
        ExpressionEngine.locale = Locale(identifier: "en_US")
    }

    func eval(_ s: String) -> Value { ExpressionEngine.evaluate(s, scope: scope) }

    func testArithmeticAndPrecedence() {
        XCTAssertEqual(eval("1 + 2 * 3"), 7)
        XCTAssertEqual(eval("(1 + 2) * 3"), 9)
        XCTAssertEqual(eval("count + 1"), 4)
        XCTAssertEqual(eval("price * qty"), 25)
        XCTAssertEqual(eval("10 % 4"), 2)
        XCTAssertEqual(eval("-count + 10"), 7)
        XCTAssertEqual(eval("7 / 0"), 0)
    }

    func testStringsAndConcatenation() {
        XCTAssertEqual(eval("'Hi ' + name"), "Hi Rey")
        XCTAssertEqual(eval("\"Room \" + 1"), "Room 1")
        XCTAssertEqual(eval("upper(name)"), "REY")
        XCTAssertEqual(eval("name.lower()"), "rey")
        XCTAssertEqual(eval("name.count"), 3)
    }

    func testComparisonAndLogic() {
        XCTAssertEqual(eval("count > 2 && isOn"), true)
        XCTAssertEqual(eval("count >= 5 or name == 'rey'"), true)
        XCTAssertEqual(eval("not isOn"), false)
        XCTAssertEqual(eval("count = 3"), true)
        XCTAssertEqual(eval("count != 3"), false)
        XCTAssertEqual(eval("isEmpty(empty)"), true)
        XCTAssertEqual(eval("count > 2 ? 'many' : 'few'"), "many")
        XCTAssertEqual(eval("'Tea' in map(cart, 'title')"), true)
        XCTAssertEqual(eval("empty ?? 'fallback'"), "fallback")
    }

    func testCollections() {
        XCTAssertEqual(eval("sum(cart, 'price')"), 10.5)
        XCTAssertEqual(eval("count(cart)"), 2)
        XCTAssertEqual(eval("cart.count"), 2)
        XCTAssertEqual(eval("cart[1].title"), "Cake")
        XCTAssertEqual(eval("cart.first.title"), "Tea")
        XCTAssertEqual(eval("user.address.city"), "Manila")
        XCTAssertEqual(eval("max(3, 9, 4)"), 9)
        XCTAssertEqual(eval("join(map(cart, 'title'), ' & ')"), "Tea & Cake")
        XCTAssertEqual(eval("[1, 2, 3].count"), 3)
        XCTAssertEqual(eval("{a: 1, 'b': 2}.b"), 2)
        XCTAssertEqual(eval("filter(cart, 'title', 'Cake').count"), 1)
    }

    func testFormatting() {
        XCTAssertEqual(eval("currency(1234.5)"), "$1,234.50")
        XCTAssertEqual(eval("currency(2000)"), "$2,000")
        XCTAssertEqual(eval("percent(0.425, 1)"), "42.5%")
        XCTAssertEqual(eval("compact(1530000)"), "1.5M")
        XCTAssertEqual(eval("format(3.14159, 2)"), "3.14")
        XCTAssertEqual(eval("round(2.567, 1)"), 2.6)
        XCTAssertEqual(eval("pluralize(3, 'task')"), "3 tasks")
        XCTAssertEqual(eval("isEmail('a@b.co')"), true)
        XCTAssertEqual(eval("isEmail('nope')"), false)
    }

    func testDates() {
        XCTAssertEqual(eval("formatDate('2026-11-22T10:00:00Z', 'yyyy')"), "2026")
        XCTAssertEqual(eval("daysBetween('2026-01-01', '2026-01-11')"), 10)
    }

    func testInterpolation() {
        XCTAssertEqual(Template.render("Hello, {{user.name}}! You have {{count}} items.", scope: scope), "Hello, Ana! You have 3 items.")
        XCTAssertEqual(Template.render("Total: {{currency(sum(cart, 'price'))}}", scope: scope), "Total: $10.50")
        XCTAssertEqual(Template.resolve("{{count * 2}}", scope: scope), 6)
        XCTAssertEqual(Template.resolve("{{isOn}}", scope: scope), true)
        XCTAssertEqual(Template.render("No templates", scope: scope), "No templates")
        XCTAssertEqual(Template.render("Broken {{", scope: scope), "Broken {{")
        XCTAssertEqual(Template.referencedNames(in: "{{count + qty}} and {{user.name}}"), ["count", "qty", "user"])
    }

    func testLenientErrors() {
        XCTAssertEqual(eval("unknownVar"), .null)
        XCTAssertEqual(eval("Just words"), "Just words")
        XCTAssertNotNil(ExpressionEngine.validate("count >"))
        XCTAssertNil(ExpressionEngine.validate("count > 1"))
    }
}

final class MockHost: RuntimeHost {
    var events: [String] = []
    var alertChoice = 1
    func navigate(to screenID: String, style: String) { events.append("nav:\(screenID):\(style)") }
    func goBack() { events.append("back") }
    func switchTab(to screenID: String) { events.append("tab:\(screenID)") }
    func presentAlert(title: String, message: String, buttons: [String], destructiveIndex: Int?) async -> Int {
        events.append("alert:\(title):\(message)")
        return buttons.count > 1 ? alertChoice : 0
    }
    func showToast(_ message: String, style: String) { events.append("toast:\(style):\(message)") }
    func openURL(_ url: String) { events.append("open:\(url)") }
    func share(_ text: String) { events.append("share:\(text)") }
    func copy(_ text: String) { events.append("copy:\(text)") }
    func haptic(_ style: String) { events.append("haptic:\(style)") }
    func scheduleNotification(title: String, body: String, seconds: Double) { events.append("notify:\(title)") }
}

final class MockHTTP: HTTPClient {
    var responses: [String: (Int, String)] = [:]
    var requests: [HTTPRequest] = []
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard let r = responses[request.url] else { throw HTTPClientError(message: "offline") }
        return HTTPResponse(status: r.0, body: Data(r.1.utf8))
    }
}

final class RuntimeTests: XCTestCase {
    func makeRunner() -> (ActionRunner, MockHost, MockHTTP) {
        var project = Project(name: "Test")
        let home = Screen(name: "Home")
        let details = Screen(name: "Details")
        project.addScreen(home)
        project.addScreen(details)
        project.variables = [
            Variable(name: "count", type: .number, initial: 0),
            Variable(name: "todos", type: .list, initial: ["Buy milk"]),
            Variable(name: "newTodo", type: .text, initial: "Walk dog"),
            Variable(name: "dark", type: .bool, initial: false),
            Variable(name: "temp", type: .number),
            Variable(name: "total", type: .number, formula: "count * 10"),
            Variable(name: "email", type: .text, initial: "bad"),
        ]
        let state = StateStore(variables: project.variables, persistence: MemoryPersistence())
        let http = MockHTTP()
        let host = MockHost()
        let runner = ActionRunner(project: project, state: state, http: http, host: host)
        return (runner, host, http)
    }

    func testDataActions() async {
        let (runner, _, _) = makeRunner()
        await runner.run([.increment("count"), .increment("count", by: 4), .decrement("count")])
        XCTAssertEqual(runner.state.value("count"), 4)
        XCTAssertEqual(runner.state.value("total"), 40, "computed variable follows its formula")
        await runner.run([.set("count", "count * 2")])
        XCTAssertEqual(runner.state.value("count"), 8)
        await runner.run([.set("newTodo", "Call mom")])
        XCTAssertEqual(runner.state.value("newTodo"), "Call mom")
        await runner.run([.append("todos", item: "{{newTodo}}"), .toggle("dark")])
        XCTAssertEqual(runner.state.value("todos"), ["Buy milk", "Call mom"])
        XCTAssertEqual(runner.state.value("dark"), true)
        await runner.run([.remove("todos", index: "0")])
        XCTAssertEqual(runner.state.value("todos"), ["Call mom"])
        await runner.run([.append("todos", item: "{\"title\": \"{{newTodo}}\", \"done\": false}")])
        XCTAssertEqual(runner.state.value("todos")[1], ["title": "Call mom", "done": false])
        var update = Action(kind: .updateItem)
        update.params = ["variable": "todos", "index": "1", "field": "done", "value": "{{!item.done}}"]
        await runner.run([update])
        XCTAssertEqual(runner.state.value("todos")[1]["done"], true)
        await runner.run([.clear("todos")])
        XCTAssertEqual(runner.state.value("todos"), [])
    }

    func testNavigationAndFeedback() async {
        let (runner, host, _) = makeRunner()
        await runner.run([.navigate("Details", style: "sheet"), .back(), .toast("Saved"), .haptic("light"), .open("https://apple.com")])
        let detailsID = runner.project.screen(named: "Details")!.id
        XCTAssertEqual(host.events, ["nav:\(detailsID):sheet", "back", "toast:success:Saved", "haptic:light", "open:https://apple.com"])
    }

    func testConditionsConfirmAndValidation() async {
        let (runner, host, _) = makeRunner()
        runner.state.set("count", 5)
        await runner.run([.when("count > 3", then: [.toast("big")], else: [.toast("small")])])
        XCTAssertEqual(host.events.last, "toast:success:big")
        host.alertChoice = 0
        await runner.run([.confirm("Delete?", then: [.toast("deleted")])])
        XCTAssertEqual(host.events.last, "alert:Delete?:")
        let ok = await runner.run([.validate("isEmail(email)", message: "Enter a valid email", then: []), .toast("never")])
        XCTAssertFalse(ok)
        XCTAssertEqual(host.events.last, "toast:error:Enter a valid email")
    }

    func testAPIRequest() async {
        let (runner, host, http) = makeRunner()
        http.responses["https://api.test/weather?city=Manila"] = (200, "{\"current\": {\"temperature_2m\": 31.4}}")
        await runner.run([.api("https://api.test/weather?city={{city}}", into: "temp", path: "current.temperature_2m", then: [.toast("Now {{$result}}°")])],
                         scope: runner.baseScope(["city": "Manila"]))
        XCTAssertEqual(runner.state.value("temp"), 31.4)
        XCTAssertEqual(host.events.last, "toast:success:Now 31.4°")
        await runner.run([.api("https://api.test/missing", then: [], otherwise: [.toast("failed: {{$error}}", style: "error")])])
        XCTAssertEqual(host.events.last, "toast:error:failed: offline")
    }

    func testPersistence() {
        let p = MemoryPersistence()
        let vars = [Variable(name: "score", type: .number, initial: 1, persist: true)]
        let s1 = StateStore(variables: vars, persistence: p)
        s1.set("score", 99)
        let s2 = StateStore(variables: vars, persistence: p)
        XCTAssertEqual(s2.value("score"), 99)
        s2.reset()
        XCTAssertEqual(s2.value("score"), 1)
    }
}
