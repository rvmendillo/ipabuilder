import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Persistence

public protocol PersistenceBackend: AnyObject {
    func load(_ key: String) -> Data?
    func save(_ key: String, _ data: Data?)
}

public final class MemoryPersistence: PersistenceBackend {
    public var storage: [String: Data] = [:]
    public init() {}
    public func load(_ key: String) -> Data? { storage[key] }
    public func save(_ key: String, _ data: Data?) { storage[key] = data }
}

public final class UserDefaultsPersistence: PersistenceBackend {
    let defaults: UserDefaults
    let prefix: String
    public init(defaults: UserDefaults = .standard, prefix: String) { self.defaults = defaults; self.prefix = prefix }
    public func load(_ key: String) -> Data? { defaults.data(forKey: prefix + key) }
    public func save(_ key: String, _ data: Data?) {
        if let d = data { defaults.set(d, forKey: prefix + key) } else { defaults.removeObject(forKey: prefix + key) }
    }
}

// MARK: - State

/// Holds the live values of a project's variables.
public final class StateStore: ValueLookup {
    public private(set) var values: [String: Value] = [:]
    public private(set) var definitions: [String: Variable] = [:]
    public var onChange: ((String) -> Void)?
    let persistence: PersistenceBackend?
    private var evaluating = Set<String>()

    public init(variables: [Variable], persistence: PersistenceBackend? = nil) {
        self.persistence = persistence
        configure(variables)
    }

    public func configure(_ variables: [Variable]) {
        var defs: [String: Variable] = [:]
        for v in variables { defs[v.name] = v }
        definitions = defs
        for v in variables where values[v.name] == nil {
            if v.persist, let data = persistence?.load(v.name), let saved = Value.fromJSONData(data) {
                values[v.name] = v.type.coerce(saved)
            } else {
                values[v.name] = v.initial
            }
        }
        for key in values.keys where defs[key] == nil { values.removeValue(forKey: key) }
    }

    public func lookup(_ name: String) -> Value? {
        if let def = definitions[name], let formula = def.formula, !formula.trimmingCharacters(in: .whitespaces).isEmpty {
            guard !evaluating.contains(name) else { return .null }
            evaluating.insert(name)
            defer { evaluating.remove(name) }
            let f = formula.trimmingCharacters(in: .whitespaces)
            let v = Template.containsTemplate(f) ? Template.resolve(f, scope: Scope(globals: self)) : ExpressionEngine.evaluate(f, scope: Scope(globals: self))
            return def.type.coerce(v)
        }
        if let v = values[name] { return v }
        // Case-insensitive fallback helps hand-written expressions.
        if let key = values.keys.first(where: { $0.lowercased() == name.lowercased() }) { return values[key] }
        return nil
    }

    public func value(_ name: String) -> Value { lookup(name) ?? .null }

    public func set(_ name: String, _ newValue: Value) {
        let key = definitions[name] != nil ? name : (definitions.keys.first { $0.lowercased() == name.lowercased() } ?? name)
        let def = definitions[key]
        let v = def.map { $0.type.coerce(newValue) } ?? newValue
        if values[key] == v { return }
        values[key] = v
        if def?.persist == true, let data = try? JSONEncoder().encode(v) { persistence?.save(key, data) }
        onChange?(key)
    }

    /// Declares a variable on the fly (used when a binding references an undeclared name).
    public func ensure(_ name: String, kind: ValueKind, initial: Value? = nil) {
        guard definitions[name] == nil else { return }
        let v = Variable(name: name, type: kind, initial: initial)
        definitions[name] = v
        values[name] = v.initial
    }

    public func reset(_ names: [String]? = nil) {
        let targets = names?.isEmpty == false ? names! : Array(definitions.keys)
        for n in targets {
            guard let def = definitions[n] else { continue }
            values[n] = def.initial
            if def.persist { persistence?.save(n, nil) }
            onChange?(n)
        }
    }

    public var snapshot: [String: Value] {
        var out = values
        for (name, def) in definitions where def.isComputed { out[name] = lookup(name) ?? .null }
        return out
    }
}

// MARK: - Networking

public struct HTTPRequest: Hashable {
    public var url: String
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    public init(url: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url; self.method = method; self.headers = headers; self.body = body
    }
}

public struct HTTPResponse {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    public init(status: Int, headers: [String: String] = [:], body: Data) { self.status = status; self.headers = headers; self.body = body }
    public var ok: Bool { (200..<300).contains(status) }
    public var json: Value { Value.fromJSONData(body) ?? .string(String(data: body, encoding: .utf8) ?? "") }
}

public protocol HTTPClient: AnyObject {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public struct HTTPClientError: LocalizedError, CustomStringConvertible {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
    public var errorDescription: String? { message }
}

public final class URLSessionHTTPClient: HTTPClient {
    let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url.trimmingCharacters(in: .whitespaces)) else { throw HTTPClientError(message: "Invalid URL: \(request.url)") }
        var r = URLRequest(url: url)
        r.httpMethod = request.method.uppercased()
        r.timeoutInterval = 30
        for (k, v) in request.headers { r.setValue(v, forHTTPHeaderField: k) }
        if let b = request.body, r.httpMethod != "GET" {
            r.httpBody = b
            if r.value(forHTTPHeaderField: "Content-Type") == nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        }
        let (data, response) = try await session.data(for: r)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (k, v) in http?.allHeaderFields ?? [:] { headers["\(k)"] = "\(v)" }
        return HTTPResponse(status: http?.statusCode ?? 200, headers: headers, body: data)
    }
}

// MARK: - Host

/// UI side effects the action runner needs. The SwiftUI runtime implements this on the main actor.
@MainActor
public protocol RuntimeHost: AnyObject {
    func navigate(to screenID: String, style: String)
    func goBack()
    func switchTab(to screenID: String)
    /// Presents an alert and returns the index of the tapped button.
    func presentAlert(title: String, message: String, buttons: [String], destructiveIndex: Int?) async -> Int
    func showToast(_ message: String, style: String)
    func openURL(_ url: String)
    func share(_ text: String)
    func copy(_ text: String)
    func haptic(_ style: String)
    func scheduleNotification(title: String, body: String, seconds: Double)
}

// MARK: - Value resolution

public enum ValueResolver {
    /// Resolves an action parameter: templates, JSON with templates, expressions over known names, or literals.
    public static func resolve(_ raw: Value, scope: Scope) -> Value {
        guard case .string(let s) = raw else { return Template.resolve(raw, scope: scope) }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .string("") }
        if let first = t.first, first == "{" || first == "[", !t.hasPrefix("{{"), let json = Value.fromJSONString(t) {
            return resolveTemplates(in: json, scope: scope)
        }
        if Template.containsTemplate(t) { return Template.resolve(t, scope: scope) }
        if let node = try? ExpressionEngine.parse(t) {
            let names = Template.referencedNames(in: t)
            let known = names.allSatisfy { scope.lookup($0) != nil || ["now", "today", "pi"].contains($0.lowercased()) }
            let isPlainWord = names.count == 1 && !t.contains(where: { "+-*/%()<>=!&|?[].\"'".contains($0) }) && scope.lookup(t) == nil
            if known && !isPlainWord {
                return ExpressionEngine.eval(node, scope)
            }
            if names.isEmpty { return ExpressionEngine.eval(node, scope) }
        }
        return Value.parseLiteral(t)
    }

    public static func resolveTemplates(in v: Value, scope: Scope) -> Value {
        switch v {
        case .string(let s): return Template.containsTemplate(s) ? Template.resolve(s, scope: scope) : v
        case .array(let a): return .array(a.map { resolveTemplates(in: $0, scope: scope) })
        case .object(let o): return .object(o.mapValues { resolveTemplates(in: $0, scope: scope) })
        default: return v
        }
    }

    /// Evaluates a condition written either as `count > 3` or `{{count > 3}}`.
    public static func condition(_ raw: String, scope: Scope) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if Template.containsTemplate(t) { return Template.resolve(t, scope: scope).boolValue }
        return ExpressionEngine.evaluate(t, scope: scope).boolValue
    }
}

// MARK: - Action runner

/// Executes action flows. Main-actor isolated so state and UI changes never race; network calls suspend off the main thread.
@MainActor
public final class ActionRunner {
    public let state: StateStore
    public weak var host: RuntimeHost?
    public var http: HTTPClient
    public var project: Project
    public private(set) var log: [String] = []
    public var onLog: ((String) -> Void)?
    public var maxDepth = 24

    public init(project: Project, state: StateStore, http: HTTPClient = URLSessionHTTPClient(), host: RuntimeHost? = nil) {
        self.project = project
        self.state = state
        self.http = http
        self.host = host
    }

    func record(_ s: String) {
        log.append(s)
        if log.count > 300 { log.removeFirst(log.count - 300) }
        onLog?(s)
    }

    public func baseScope(_ locals: [String: Value] = [:]) -> Scope { Scope(locals: locals, globals: state) }

    func screenID(_ raw: String) -> String? {
        if project.screen(id: raw) != nil { return raw }
        return project.screen(named: raw)?.id
    }

    /// Runs actions in order. Returns false if the chain was stopped (validation failure).
    @discardableResult
    public func run(_ actions: [Action], scope: Scope? = nil, depth: Int = 0) async -> Bool {
        let scope = scope ?? baseScope()
        guard depth < maxDepth else { record("⚠︎ Action depth limit reached"); return false }
        for action in actions where action.enabled {
            let keepGoing = await perform(action, scope: scope, depth: depth)
            if !keepGoing { return false }
        }
        return true
    }

    func string(_ action: Action, _ key: String, _ scope: Scope) -> String {
        Template.render(action.string(key), scope: scope)
    }

    func number(_ action: Action, _ key: String, _ scope: Scope, default d: Double) -> Double {
        let v = action.param(key)
        if v.isNull || v.stringValue.isEmpty { return d }
        return ValueResolver.resolve(v, scope: scope).numberValue ?? d
    }

    func perform(_ action: Action, scope: Scope, depth: Int) async -> Bool {
        record(ActionRegistry.describe(action, screenName: { self.project.screenName($0) }))
        switch action.kind {
        case .navigate:
            guard let id = screenID(string(action, "screen", scope)) else { record("⚠︎ Missing screen"); return true }
            let style = action.string("style").isEmpty ? "push" : action.string("style")
            host?.navigate(to: id, style: style)
        case .back:
            host?.goBack()
        case .switchTab:
            if let id = screenID(string(action, "screen", scope)) { host?.switchTab(to: id) }
        case .alert:
            _ = await host?.presentAlert(title: string(action, "title", scope), message: string(action, "message", scope), buttons: ["OK"], destructiveIndex: nil)
            if !action.then.isEmpty { return await run(action.then, scope: scope, depth: depth + 1) }
        case .confirm:
            let label = action.string("confirmLabel").isEmpty ? "Confirm" : string(action, "confirmLabel", scope)
            let destructive = action.param("destructive").boolValue
            let choice = await host?.presentAlert(title: string(action, "title", scope), message: string(action, "message", scope),
                                                  buttons: ["Cancel", label], destructiveIndex: destructive ? 1 : nil) ?? 1
            if choice == 1 { return await run(action.then, scope: scope, depth: depth + 1) }
            return await run(action.otherwise, scope: scope, depth: depth + 1)
        case .toast:
            host?.showToast(string(action, "message", scope), style: action.string("style").isEmpty ? "success" : action.string("style"))
        case .setVariable:
            let name = action.string("variable")
            guard !name.isEmpty else { return true }
            state.set(name, ValueResolver.resolve(action.param("value"), scope: scope))
        case .toggleVariable:
            let name = action.string("variable")
            state.set(name, .bool(!state.value(name).boolValue))
        case .increment, .decrement:
            let name = action.string("variable")
            let amount = number(action, "amount", scope, default: 1)
            var v = (state.value(name).numberValue ?? 0) + (action.kind == .increment ? amount : -amount)
            if action.kind == .increment, !action.param("max").stringValue.isEmpty, let mx = ValueResolver.resolve(action.param("max"), scope: scope).numberValue { v = min(v, mx) }
            if action.kind == .decrement, !action.param("min").stringValue.isEmpty, let mn = ValueResolver.resolve(action.param("min"), scope: scope).numberValue { v = max(v, mn) }
            state.set(name, .number(v))
        case .appendItem:
            let name = action.string("variable")
            var list = state.value(name).arrayValue
            let item = ValueResolver.resolve(action.param("item"), scope: scope)
            if action.string("position") == "start" { list.insert(item, at: 0) } else { list.append(item) }
            state.set(name, .array(list))
        case .removeItem:
            let name = action.string("variable")
            var list = state.value(name).arrayValue
            let target = ValueResolver.resolve(action.param("index"), scope: scope)
            if case .number(let n) = target, list.indices.contains(Int(n)) {
                list.remove(at: Int(n))
            } else if let i = list.firstIndex(where: { ExpressionEngine.equals($0, target) }) {
                list.remove(at: i)
            } else if !list.isEmpty && target.isNull {
                list.removeLast()
            }
            state.set(name, .array(list))
        case .updateItem:
            let name = action.string("variable")
            var list = state.value(name).arrayValue
            let idx = Int(ValueResolver.resolve(action.param("index"), scope: scope).numberValue ?? -1)
            guard list.indices.contains(idx) else { return true }
            let field = action.string("field")
            let newValue = ValueResolver.resolve(action.param("value"), scope: scope.with("item", list[idx]))
            if field.isEmpty {
                list[idx] = newValue
            } else {
                var obj = list[idx].objectValue
                obj[field] = newValue
                list[idx] = .object(obj)
            }
            state.set(name, .array(list))
        case .clearList:
            state.set(action.string("variable"), .array([]))
        case .resetVariables:
            let names = action.string("variables").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            state.reset(names)
        case .condition:
            let ok = ValueResolver.condition(action.string("condition"), scope: scope)
            return await run(ok ? action.then : action.otherwise, scope: scope, depth: depth + 1)
        case .validate:
            if ValueResolver.condition(action.string("condition"), scope: scope) {
                return await run(action.then, scope: scope, depth: depth + 1)
            }
            let msg = string(action, "message", scope)
            host?.haptic("error")
            host?.showToast(msg.isEmpty ? "Please check your input." : msg, style: "error")
            return false
        case .delay:
            let s = max(0, min(60, number(action, "seconds", scope, default: 1)))
            try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
        case .apiRequest:
            return await performAPI(action, scope: scope, depth: depth)
        case .openURL:
            host?.openURL(string(action, "url", scope))
        case .share:
            host?.share(string(action, "text", scope))
        case .copy:
            host?.copy(string(action, "text", scope))
            host?.showToast("Copied", style: "info")
        case .haptic:
            host?.haptic(action.string("style").isEmpty ? "success" : action.string("style"))
        case .notify:
            host?.scheduleNotification(title: string(action, "title", scope), body: string(action, "body", scope), seconds: number(action, "seconds", scope, default: 5))
        }
        return true
    }

    func performAPI(_ action: Action, scope: Scope, depth: Int) async -> Bool {
        var url = string(action, "url", scope)
        var method = action.string("method").isEmpty ? "GET" : action.string("method").uppercased()
        var headers: [String: String] = [:]
        var bodyTemplate = action.string("body")
        var resultVariable = action.string("resultVariable")
        var resultPath = action.string("resultPath")
        if let endpointName = Optional(action.string("endpoint")), !endpointName.isEmpty,
           let ep = project.apis.first(where: { $0.name.lowercased() == endpointName.lowercased() || $0.id == endpointName }) {
            if url.isEmpty { url = Template.render(ep.url, scope: scope) }
            if action.string("method").isEmpty { method = ep.method.uppercased() }
            headers = ep.headers.mapValues { Template.render($0, scope: scope) }
            if bodyTemplate.isEmpty { bodyTemplate = ep.body }
            if resultVariable.isEmpty { resultVariable = ep.resultVariable ?? "" }
            if resultPath.isEmpty { resultPath = ep.resultPath }
        }
        var body: Data?
        if !bodyTemplate.trimmingCharacters(in: .whitespaces).isEmpty {
            let resolved = ValueResolver.resolve(.string(bodyTemplate), scope: scope)
            switch resolved {
            case .object, .array: body = try? JSONEncoder().encode(resolved)
            default: body = resolved.stringValue.data(using: .utf8)
            }
        }
        do {
            let response = try await http.send(HTTPRequest(url: url, method: method, headers: headers, body: body))
            let json = response.json
            let extracted = resultPath.isEmpty ? json : json.value(atPath: resultPath)
            if !resultVariable.isEmpty { state.set(resultVariable, extracted) }
            let next = scope.with(["$response": json, "$status": .number(Double(response.status)), "$result": extracted])
            if response.ok {
                record("✓ \(method) \(url) → \(response.status)")
                return await run(action.then, scope: next, depth: depth + 1)
            }
            record("✗ \(method) \(url) → \(response.status)")
            return await run(action.otherwise, scope: next.with("$error", .string("HTTP \(response.status)")), depth: depth + 1)
        } catch {
            record("✗ \(method) \(url): \(error)")
            if action.otherwise.isEmpty { host?.showToast("Network error: \(error.localizedDescription)", style: "error") }
            return await run(action.otherwise, scope: scope.with("$error", .string("\(error.localizedDescription)")), depth: depth + 1)
        }
    }
}
