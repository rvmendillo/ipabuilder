import Foundation

// MARK: - Events

public enum EventKind: String, Codable, CaseIterable, Hashable {
    case tap, longPress, change, submit, appear, delete, refresh

    public var title: String {
        switch self {
        case .tap: return "On Tap"
        case .longPress: return "On Long Press"
        case .change: return "On Change"
        case .submit: return "On Submit"
        case .appear: return "On Appear"
        case .delete: return "On Swipe Delete"
        case .refresh: return "On Pull to Refresh"
        }
    }

    public var symbol: String {
        switch self {
        case .tap: return "hand.tap"
        case .longPress: return "hand.point.up.left"
        case .change: return "arrow.triangle.2.circlepath"
        case .submit: return "return"
        case .appear: return "eye"
        case .delete: return "trash"
        case .refresh: return "arrow.clockwise"
        }
    }
}

public struct EventHandler: Codable, Hashable, Identifiable {
    public var id: String
    public var event: EventKind
    public var actions: [Action]

    public init(id: String = IDGen.short("e"), event: EventKind, actions: [Action] = []) {
        self.id = id; self.event = event; self.actions = actions
    }

    enum CodingKeys: String, CodingKey { case id, event, actions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, IDGen.short("e")); event = c.value(.event, .tap); actions = c.value(.actions, [])
    }

    public func clonedWithNewIDs() -> EventHandler {
        EventHandler(event: event, actions: actions.map { $0.clonedWithNewIDs() })
    }
}

// MARK: - Actions

public enum ActionKind: String, Codable, CaseIterable, Hashable {
    case navigate, back, switchTab, alert, confirm, toast
    case setVariable, toggleVariable, increment, decrement, appendItem, removeItem, updateItem, clearList, resetVariables
    case condition, apiRequest, openURL, share, copy, haptic, delay, notify, validate
}

public struct Action: Codable, Hashable, Identifiable {
    public var id: String
    public var kind: ActionKind
    public var params: [String: Value]
    public var then: [Action]
    public var otherwise: [Action]
    public var enabled: Bool

    public init(id: String = IDGen.short("x"), kind: ActionKind, params: [String: Value] = [:], then: [Action] = [], otherwise: [Action] = [], enabled: Bool = true) {
        self.id = id; self.kind = kind; self.params = params; self.then = then; self.otherwise = otherwise; self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey { case id, kind, params, then, otherwise, enabled }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, IDGen.short("x"))
        kind = c.value(.kind, .toast)
        params = c.value(.params, [:])
        then = c.value(.then, [])
        otherwise = c.value(.otherwise, [])
        enabled = c.value(.enabled, true)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        if !params.isEmpty { try c.encode(params, forKey: .params) }
        if !then.isEmpty { try c.encode(then, forKey: .then) }
        if !otherwise.isEmpty { try c.encode(otherwise, forKey: .otherwise) }
        if !enabled { try c.encode(enabled, forKey: .enabled) }
    }

    public func param(_ key: String) -> Value { params[key] ?? .null }
    public func string(_ key: String) -> String { params[key]?.stringValue ?? "" }

    public func clonedWithNewIDs() -> Action {
        var a = self
        a.id = IDGen.short("x")
        a.then = then.map { $0.clonedWithNewIDs() }
        a.otherwise = otherwise.map { $0.clonedWithNewIDs() }
        return a
    }

    // MARK: Convenience constructors

    public static func navigate(_ screenID: String, style: String = "push") -> Action { Action(kind: .navigate, params: ["screen": .string(screenID), "style": .string(style)]) }
    public static func back() -> Action { Action(kind: .back) }
    public static func switchTab(_ screenID: String) -> Action { Action(kind: .switchTab, params: ["screen": .string(screenID)]) }
    public static func alert(_ title: String, _ message: String = "") -> Action { Action(kind: .alert, params: ["title": .string(title), "message": .string(message)]) }
    public static func confirm(_ title: String, _ message: String = "", confirmLabel: String = "Confirm", destructive: Bool = false, then: [Action]) -> Action {
        Action(kind: .confirm, params: ["title": .string(title), "message": .string(message), "confirmLabel": .string(confirmLabel), "destructive": .bool(destructive)], then: then)
    }
    public static func toast(_ message: String, style: String = "success") -> Action { Action(kind: .toast, params: ["message": .string(message), "style": .string(style)]) }
    public static func set(_ variable: String, _ value: String) -> Action { Action(kind: .setVariable, params: ["variable": .string(variable), "value": .string(value)]) }
    public static func toggle(_ variable: String) -> Action { Action(kind: .toggleVariable, params: ["variable": .string(variable)]) }
    public static func increment(_ variable: String, by: Double = 1) -> Action { Action(kind: .increment, params: ["variable": .string(variable), "amount": .number(by)]) }
    public static func decrement(_ variable: String, by: Double = 1) -> Action { Action(kind: .decrement, params: ["variable": .string(variable), "amount": .number(by)]) }
    public static func append(_ list: String, item: String) -> Action { Action(kind: .appendItem, params: ["variable": .string(list), "item": .string(item)]) }
    public static func remove(_ list: String, index: String) -> Action { Action(kind: .removeItem, params: ["variable": .string(list), "index": .string(index)]) }
    public static func clear(_ list: String) -> Action { Action(kind: .clearList, params: ["variable": .string(list)]) }
    public static func when(_ condition: String, then: [Action], else otherwise: [Action] = []) -> Action {
        Action(kind: .condition, params: ["condition": .string(condition)], then: then, otherwise: otherwise)
    }
    public static func api(_ url: String, method: String = "GET", into variable: String = "", path: String = "", body: String = "", then: [Action] = [], otherwise: [Action] = []) -> Action {
        Action(kind: .apiRequest, params: ["url": .string(url), "method": .string(method), "resultVariable": .string(variable), "resultPath": .string(path), "body": .string(body)], then: then, otherwise: otherwise)
    }
    public static func open(_ url: String) -> Action { Action(kind: .openURL, params: ["url": .string(url)]) }
    public static func share(_ text: String) -> Action { Action(kind: .share, params: ["text": .string(text)]) }
    public static func copy(_ text: String) -> Action { Action(kind: .copy, params: ["text": .string(text)]) }
    public static func haptic(_ style: String = "success") -> Action { Action(kind: .haptic, params: ["style": .string(style)]) }
    public static func delay(_ seconds: Double) -> Action { Action(kind: .delay, params: ["seconds": .number(seconds)]) }
    public static func notify(_ title: String, _ body: String, after seconds: Double = 5) -> Action {
        Action(kind: .notify, params: ["title": .string(title), "body": .string(body), "seconds": .number(seconds)])
    }
    public static func validate(_ condition: String, message: String, then: [Action]) -> Action {
        Action(kind: .validate, params: ["condition": .string(condition), "message": .string(message)], then: then)
    }
}

// MARK: - Action specs (drive the logic editor, AI compiler and validation)

public enum ParamKind: Hashable {
    case text, multiline, expression, variable, listVariable, screen, number, bool, url, json
    case options([String])
}

public struct ParamSpec: Hashable {
    public let key: String
    public let label: String
    public let kind: ParamKind
    public let placeholder: String
    public let required: Bool
    public let defaultValue: Value

    public init(_ key: String, _ label: String, _ kind: ParamKind, placeholder: String = "", required: Bool = false, defaultValue: Value = .null) {
        self.key = key; self.label = label; self.kind = kind; self.placeholder = placeholder; self.required = required; self.defaultValue = defaultValue
    }
}

public struct ActionSpec: Hashable {
    public let kind: ActionKind
    public let title: String
    public let symbol: String
    public let category: String
    public let summary: String
    public let params: [ParamSpec]
    public let thenLabel: String?
    public let otherwiseLabel: String?
}

public enum ActionRegistry {
    public static let all: [ActionSpec] = [
        ActionSpec(kind: .navigate, title: "Navigate", symbol: "arrow.right.square", category: "Navigation", summary: "Open another screen",
                   params: [ParamSpec("screen", "Screen", .screen, required: true),
                            ParamSpec("style", "Presentation", .options(["push", "sheet", "fullScreen", "replace"]), defaultValue: "push")],
                   thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .back, title: "Go Back", symbol: "chevron.backward.circle", category: "Navigation", summary: "Pop or dismiss the current screen",
                   params: [], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .switchTab, title: "Switch Tab", symbol: "rectangle.split.3x1", category: "Navigation", summary: "Select a tab",
                   params: [ParamSpec("screen", "Tab screen", .screen, required: true)], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .alert, title: "Show Alert", symbol: "exclamationmark.bubble", category: "Feedback", summary: "Display an alert",
                   params: [ParamSpec("title", "Title", .text, placeholder: "Saved!", required: true), ParamSpec("message", "Message", .multiline)],
                   thenLabel: "After OK", otherwiseLabel: nil),
        ActionSpec(kind: .confirm, title: "Confirm", symbol: "questionmark.bubble", category: "Feedback", summary: "Ask before continuing",
                   params: [ParamSpec("title", "Title", .text, required: true), ParamSpec("message", "Message", .multiline),
                            ParamSpec("confirmLabel", "Confirm button", .text, defaultValue: "Confirm"), ParamSpec("destructive", "Destructive", .bool, defaultValue: false)],
                   thenLabel: "If confirmed", otherwiseLabel: "If cancelled"),
        ActionSpec(kind: .toast, title: "Show Toast", symbol: "text.bubble", category: "Feedback", summary: "Show a short banner",
                   params: [ParamSpec("message", "Message", .text, required: true), ParamSpec("style", "Style", .options(["success", "info", "warning", "error"]), defaultValue: "success")],
                   thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .setVariable, title: "Set Variable", symbol: "equal.square", category: "Data", summary: "Assign a value or expression",
                   params: [ParamSpec("variable", "Variable", .variable, required: true), ParamSpec("value", "Value", .expression, placeholder: "{{count + 1}}")],
                   thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .toggleVariable, title: "Toggle", symbol: "switch.2", category: "Data", summary: "Flip a yes/no variable",
                   params: [ParamSpec("variable", "Variable", .variable, required: true)], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .increment, title: "Increment", symbol: "plus.circle", category: "Data", summary: "Add to a number",
                   params: [ParamSpec("variable", "Variable", .variable, required: true), ParamSpec("amount", "By", .number, defaultValue: 1),
                            ParamSpec("max", "Maximum", .number)], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .decrement, title: "Decrement", symbol: "minus.circle", category: "Data", summary: "Subtract from a number",
                   params: [ParamSpec("variable", "Variable", .variable, required: true), ParamSpec("amount", "By", .number, defaultValue: 1),
                            ParamSpec("min", "Minimum", .number)], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .appendItem, title: "Add to List", symbol: "text.badge.plus", category: "Data", summary: "Append an item to a list",
                   params: [ParamSpec("variable", "List", .listVariable, required: true), ParamSpec("item", "Item", .expression, placeholder: "{\"title\": \"{{newTitle}}\"}"),
                            ParamSpec("position", "Position", .options(["end", "start"]), defaultValue: "end")],
                   thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .removeItem, title: "Remove from List", symbol: "text.badge.minus", category: "Data", summary: "Remove an item by index or value",
                   params: [ParamSpec("variable", "List", .listVariable, required: true), ParamSpec("index", "Index or value", .expression, placeholder: "{{index}}")],
                   thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .updateItem, title: "Update List Item", symbol: "pencil.line", category: "Data", summary: "Change a field of a list item",
                   params: [ParamSpec("variable", "List", .listVariable, required: true), ParamSpec("index", "Index", .expression, placeholder: "{{index}}"),
                            ParamSpec("field", "Field", .text, placeholder: "done"), ParamSpec("value", "Value", .expression, placeholder: "{{!item.done}}")],
                   thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .clearList, title: "Clear List", symbol: "xmark.bin", category: "Data", summary: "Remove all items",
                   params: [ParamSpec("variable", "List", .listVariable, required: true)], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .resetVariables, title: "Reset Variables", symbol: "arrow.counterclockwise", category: "Data", summary: "Restore initial values",
                   params: [ParamSpec("variables", "Variables (comma separated, empty = all)", .text)], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .condition, title: "If / Else", symbol: "arrow.triangle.branch", category: "Logic", summary: "Run actions conditionally",
                   params: [ParamSpec("condition", "Condition", .expression, placeholder: "count > 10", required: true)],
                   thenLabel: "If true", otherwiseLabel: "Else"),
        ActionSpec(kind: .validate, title: "Validate", symbol: "checkmark.shield", category: "Logic", summary: "Stop with a message unless a condition holds",
                   params: [ParamSpec("condition", "Must be true", .expression, placeholder: "isEmail(email)", required: true),
                            ParamSpec("message", "Error message", .text, placeholder: "Please enter a valid email")],
                   thenLabel: "If valid", otherwiseLabel: nil),
        ActionSpec(kind: .delay, title: "Wait", symbol: "timer", category: "Logic", summary: "Pause before the next action",
                   params: [ParamSpec("seconds", "Seconds", .number, defaultValue: 1)], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .apiRequest, title: "API Request", symbol: "network", category: "Network", summary: "Call a REST API and store the JSON",
                   params: [ParamSpec("endpoint", "Saved endpoint", .text), ParamSpec("url", "URL", .url, placeholder: "https://api.example.com/items"),
                            ParamSpec("method", "Method", .options(["GET", "POST", "PUT", "PATCH", "DELETE"]), defaultValue: "GET"),
                            ParamSpec("body", "JSON body", .json), ParamSpec("resultVariable", "Save response to", .variable),
                            ParamSpec("resultPath", "Response path", .text, placeholder: "data.items")],
                   thenLabel: "On success", otherwiseLabel: "On failure"),
        ActionSpec(kind: .openURL, title: "Open URL", symbol: "safari", category: "Device", summary: "Open a website, phone or mail link",
                   params: [ParamSpec("url", "URL", .url, placeholder: "https://apple.com", required: true)], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .share, title: "Share", symbol: "square.and.arrow.up", category: "Device", summary: "Open the share sheet",
                   params: [ParamSpec("text", "Text or URL", .text, required: true)], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .copy, title: "Copy", symbol: "doc.on.doc", category: "Device", summary: "Copy text to the clipboard",
                   params: [ParamSpec("text", "Text", .text, required: true)], thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .haptic, title: "Haptic", symbol: "iphone.radiowaves.left.and.right", category: "Device", summary: "Play haptic feedback",
                   params: [ParamSpec("style", "Style", .options(["success", "warning", "error", "light", "medium", "heavy", "selection"]), defaultValue: "success")],
                   thenLabel: nil, otherwiseLabel: nil),
        ActionSpec(kind: .notify, title: "Local Notification", symbol: "bell.badge", category: "Device", summary: "Schedule a notification",
                   params: [ParamSpec("title", "Title", .text, required: true), ParamSpec("body", "Body", .text), ParamSpec("seconds", "After seconds", .number, defaultValue: 5)],
                   thenLabel: nil, otherwiseLabel: nil),
    ]

    private static let byKind: [ActionKind: ActionSpec] = Dictionary(uniqueKeysWithValues: all.map { ($0.kind, $0) })

    public static func spec(for kind: ActionKind) -> ActionSpec { byKind[kind]! }

    public static var categories: [String] {
        var seen: [String] = []
        for s in all where !seen.contains(s.category) { seen.append(s.category) }
        return seen
    }

    /// One-line human description, e.g. "Navigate to Details (sheet)".
    public static func describe(_ action: Action, screenName: (String) -> String = { $0 }) -> String {
        switch action.kind {
        case .navigate:
            let style = action.string("style")
            return "Open \(screenName(action.string("screen")))" + (style.isEmpty || style == "push" ? "" : " as \(style)")
        case .back: return "Go back"
        case .switchTab: return "Switch to \(screenName(action.string("screen"))) tab"
        case .alert: return "Alert “\(action.string("title"))”"
        case .confirm: return "Confirm “\(action.string("title"))”"
        case .toast: return "Toast “\(action.string("message"))”"
        case .setVariable: return "Set \(action.string("variable")) = \(action.string("value"))"
        case .toggleVariable: return "Toggle \(action.string("variable"))"
        case .increment: return "\(action.string("variable")) += \(action.param("amount").stringValue.isEmpty ? "1" : action.param("amount").stringValue)"
        case .decrement: return "\(action.string("variable")) -= \(action.param("amount").stringValue.isEmpty ? "1" : action.param("amount").stringValue)"
        case .appendItem: return "Add to \(action.string("variable"))"
        case .removeItem: return "Remove from \(action.string("variable"))"
        case .updateItem: return "Update \(action.string("variable"))[\(action.string("index"))].\(action.string("field"))"
        case .clearList: return "Clear \(action.string("variable"))"
        case .resetVariables: return "Reset variables"
        case .condition: return "If \(action.string("condition"))"
        case .validate: return "Require \(action.string("condition"))"
        case .apiRequest:
            let target = action.string("endpoint").isEmpty ? action.string("url") : action.string("endpoint")
            return "\(action.string("method").isEmpty ? "GET" : action.string("method")) \(target)"
        case .openURL: return "Open \(action.string("url"))"
        case .share: return "Share \(action.string("text"))"
        case .copy: return "Copy \(action.string("text"))"
        case .haptic: return "Haptic \(action.string("style"))"
        case .delay: return "Wait \(action.param("seconds").stringValue)s"
        case .notify: return "Notify “\(action.string("title"))”"
        }
    }
}
