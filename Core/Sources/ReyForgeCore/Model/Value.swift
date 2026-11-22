import Foundation

/// A JSON-like dynamic value used for component properties, variables,
/// API responses and expression results.
public enum Value: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Value])
    case object([String: Value])
}

// MARK: - Literals

extension Value: ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
                 ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
                 ExpressibleByDictionaryLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: Value...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, Value)...) {
        var dict: [String: Value] = [:]
        for (k, v) in elements { dict[k] = v }
        self = .object(dict)
    }
}

// MARK: - Codable (plain JSON representation)

extension Value: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([Value].self) { self = .array(a); return }
        if let o = try? c.decode([String: Value].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d):
            if d.isFinite { try c.encode(d) } else { try c.encodeNil() }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - Accessors & coercion

public extension Value {
    var isNull: Bool { if case .null = self { return true }; return false }

    /// Human friendly display string ("12", "12.5", "true", JSON for collections).
    var stringValue: String {
        switch self {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .number(let d): return Value.format(number: d)
        case .string(let s): return s
        case .array, .object: return jsonString()
        }
    }

    /// Numeric coercion. Strings like "12", "1,200.50", "$9.99" and "45%" are parsed leniently.
    var numberValue: Double? {
        switch self {
        case .number(let d): return d
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Value.parseNumber(s)
        case .null: return nil
        case .array, .object: return nil
        }
    }

    /// Truthiness used by conditions and visibility rules.
    var boolValue: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let d): return d != 0 && !d.isNaN
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !(t.isEmpty || t == "false" || t == "0" || t == "no" || t == "off" || t == "null")
        case .array(let a): return !a.isEmpty
        case .object(let o): return !o.isEmpty
        }
    }

    var arrayValue: [Value] {
        switch self {
        case .array(let a): return a
        case .null: return []
        case .string(let s):
            // Allow JSON arrays stored as strings and comma separated lists.
            if let parsed = Value.fromJSONString(s), case .array(let a) = parsed { return a }
            let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return parts.map { .string($0) }
        default: return [self]
        }
    }

    var objectValue: [String: Value] {
        if case .object(let o) = self { return o }
        return [:]
    }

    subscript(key: String) -> Value {
        if case .object(let o) = self { return o[key] ?? .null }
        if case .array(let a) = self, let i = Int(key), a.indices.contains(i) { return a[i] }
        return .null
    }

    subscript(index: Int) -> Value {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    /// Follows a dotted path such as "current.temperature_2m" or "items.0.title".
    func value(atPath path: String) -> Value {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return self }
        var current = self
        for raw in trimmed.split(separator: ".") {
            var key = String(raw)
            // Support "items[0]" segments.
            var indices: [Int] = []
            while let open = key.lastIndex(of: "["), key.hasSuffix("]") {
                let inner = key[key.index(after: open)..<key.index(before: key.endIndex)]
                if let i = Int(inner) { indices.insert(i, at: 0) }
                key = String(key[..<open])
            }
            if !key.isEmpty { current = current[key] }
            for i in indices { current = current[i] }
        }
        return current
    }

    var typeName: String {
        switch self {
        case .null: return "null"
        case .bool: return "bool"
        case .number: return "number"
        case .string: return "text"
        case .array: return "list"
        case .object: return "object"
        }
    }
}

// MARK: - JSON bridging

public extension Value {
    init(any: Any?) {
        guard let any = any else { self = .null; return }
        switch any {
        case let v as Value: self = v
        case is NSNull: self = .null
        case let b as Bool where type(of: any) == Bool.self: self = .bool(b)
        case let n as NSNumber:
            #if canImport(ObjectiveC)
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue); return }
            #endif
            self = .number(n.doubleValue)
        case let i as Int: self = .number(Double(i))
        case let d as Double: self = .number(d)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { Value(any: $0) })
        case let o as [String: Any]:
            var dict: [String: Value] = [:]
            for (k, v) in o { dict[k] = Value(any: v) }
            self = .object(dict)
        default: self = .string(String(describing: any))
        }
    }

    var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map { $0.anyValue }
        case .object(let o): return o.mapValues { $0.anyValue }
        }
    }

    static func fromJSONString(_ string: String) -> Value? {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first, "[{\"".contains(first) || t == "true" || t == "false" || t == "null" || Double(t) != nil else { return nil }
        guard let data = t.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    static func fromJSONData(_ data: Data) -> Value? {
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func jsonString(pretty: Bool = false) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        guard let data = try? enc.encode(self), let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    /// Parses a literal written by a user or the AI: JSON, numbers, booleans or plain text.
    static func parseLiteral(_ raw: String) -> Value {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .string("") }
        if t == "true" { return .bool(true) }
        if t == "false" { return .bool(false) }
        if t == "null" || t == "nil" { return .null }
        if let d = Double(t), !t.hasPrefix("+") { return .number(d) }
        if let first = t.first, first == "[" || first == "{", let v = fromJSONString(t) { return v }
        if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") { return .string(String(t.dropFirst().dropLast())) }
        return .string(t)
    }
}

// MARK: - Formatting helpers

public extension Value {
    static func format(number d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "∞" : "-∞" }
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        var s = String(format: "%.6f", d)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    static func parseNumber(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if let d = Double(s) { return d }
        var negative = false
        if s.hasPrefix("-") { negative = true; s.removeFirst() }
        if s.hasPrefix("+") { s.removeFirst() }
        let currency: Set<Character> = ["$", "€", "£", "¥", "₱", "₹", "₩", "₽", "₺", "¢"]
        while let f = s.first, currency.contains(f) { s.removeFirst() }
        if s.hasPrefix("-") { negative.toggle(); s.removeFirst() }
        var percent = false
        if s.hasSuffix("%") { percent = true; s.removeLast() }
        s = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "_", with: "").trimmingCharacters(in: .whitespaces)
        guard let d = Double(s) else { return nil }
        let v = percent ? d / 100 : d
        return negative ? -v : v
    }
}

extension Value: CustomStringConvertible {
    public var description: String { stringValue }
}

/// The value types variables can be declared with.
public enum ValueKind: String, Codable, CaseIterable, Sendable {
    case text, number, bool, date, color, list, object, image

    public var title: String {
        switch self {
        case .text: return "Text"
        case .number: return "Number"
        case .bool: return "Yes / No"
        case .date: return "Date"
        case .color: return "Color"
        case .list: return "List"
        case .object: return "Object"
        case .image: return "Image"
        }
    }

    public var symbol: String {
        switch self {
        case .text: return "textformat"
        case .number: return "number"
        case .bool: return "switch.2"
        case .date: return "calendar"
        case .color: return "paintpalette"
        case .list: return "list.bullet"
        case .object: return "curlybraces"
        case .image: return "photo"
        }
    }

    public var defaultValue: Value {
        switch self {
        case .text: return .string("")
        case .number: return .number(0)
        case .bool: return .bool(false)
        case .date: return .string(ISO8601DateFormatter().string(from: Date()))
        case .color: return .string("#007AFF")
        case .list: return .array([])
        case .object: return .object([:])
        case .image: return .string("")
        }
    }

    /// Coerces an arbitrary value into this kind (used when the AI or a user supplies loose input).
    public func coerce(_ v: Value) -> Value {
        switch self {
        case .text, .color, .image, .date:
            if case .string = v { return v }
            return .string(v.stringValue)
        case .number: return .number(v.numberValue ?? 0)
        case .bool: return .bool(v.boolValue)
        case .list:
            if case .array = v { return v }
            return .array(v.arrayValue)
        case .object:
            if case .object = v { return v }
            if case .string(let s) = v, let parsed = Value.fromJSONString(s), case .object = parsed { return parsed }
            return .object([:])
        }
    }
}
