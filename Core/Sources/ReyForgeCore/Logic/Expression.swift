import Foundation

// MARK: - Scope

/// Something that can resolve variable names (the app state store implements this).
public protocol ValueLookup: AnyObject {
    func lookup(_ name: String) -> Value?
}

/// Variable resolution context for expressions: local values (item, index, $response…) over app state.
public struct Scope {
    public var locals: [String: Value]
    public weak var globals: ValueLookup?

    public init(locals: [String: Value] = [:], globals: ValueLookup? = nil) {
        self.locals = locals
        self.globals = globals
    }

    public func lookup(_ name: String) -> Value? {
        if let v = locals[name] { return v }
        return globals?.lookup(name)
    }

    public func with(_ name: String, _ value: Value) -> Scope {
        var s = self
        s.locals[name] = value
        return s
    }

    public func with(_ values: [String: Value]) -> Scope {
        var s = self
        for (k, v) in values { s.locals[k] = v }
        return s
    }

    public static let empty = Scope()
}

/// A simple dictionary-backed lookup, handy for tests and previews.
public final class DictionaryLookup: ValueLookup {
    public var values: [String: Value]
    public init(_ values: [String: Value] = [:]) { self.values = values }
    public func lookup(_ name: String) -> Value? { values[name] }
}

// MARK: - AST

public indirect enum ExprNode: Hashable {
    case literal(Value)
    case variable(String)
    case member(ExprNode, String)
    case index(ExprNode, ExprNode)
    case call(String, [ExprNode])
    case method(ExprNode, String, [ExprNode])
    case unary(String, ExprNode)
    case binary(String, ExprNode, ExprNode)
    case ternary(ExprNode, ExprNode, ExprNode)
    case array([ExprNode])
    case object([String], [ExprNode])
}

public struct ExpressionError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

// MARK: - Lexer

enum Token: Equatable {
    case number(Double)
    case string(String)
    case ident(String)
    case op(String)
    case punct(Character)
    case eof
}

struct Lexer {
    static func tokenize(_ source: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(source)
        var i = 0
        func peek(_ o: Int = 0) -> Character? { i + o < chars.count ? chars[i + o] : nil }
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber || (c == "." && (peek(1)?.isNumber ?? false)) {
                var s = ""
                while let ch = peek(), ch.isNumber || ch == "." || ch == "_" {
                    if ch != "_" { s.append(ch) }
                    i += 1
                }
                if let e = peek(), e == "e" || e == "E", let n = peek(1), n.isNumber || ((n == "-" || n == "+") && (peek(2)?.isNumber ?? false)) {
                    s.append("e"); i += 1
                    if let sign = peek(), sign == "-" || sign == "+" { s.append(sign); i += 1 }
                    while let ch = peek(), ch.isNumber { s.append(ch); i += 1 }
                }
                guard let d = Double(s) else { throw ExpressionError(message: "Invalid number \(s)") }
                tokens.append(.number(d))
                continue
            }
            if c == "\"" || c == "'" || c == "“" || c == "‘" {
                let close: Character = (c == "“") ? "”" : (c == "‘" ? "’" : c)
                i += 1
                var s = ""
                var closed = false
                while i < chars.count {
                    let ch = chars[i]
                    if ch == "\\", i + 1 < chars.count {
                        let n = chars[i + 1]
                        switch n {
                        case "n": s.append("\n")
                        case "t": s.append("\t")
                        default: s.append(n)
                        }
                        i += 2
                        continue
                    }
                    if ch == close || (close != c && ch == c) { closed = true; i += 1; break }
                    s.append(ch)
                    i += 1
                }
                if !closed { throw ExpressionError(message: "Unterminated string") }
                tokens.append(.string(s))
                continue
            }
            if c.isLetter || c == "_" || c == "$" {
                var s = ""
                while let ch = peek(), ch.isLetter || ch.isNumber || ch == "_" || ch == "$" {
                    s.append(ch); i += 1
                }
                tokens.append(.ident(s))
                continue
            }
            let two = peek(1).map { String([c, $0]) } ?? ""
            if ["==", "!=", "<=", ">=", "&&", "||", "??"].contains(two) {
                tokens.append(.op(two)); i += 2; continue
            }
            if "+-*/%<>!=".contains(c) {
                tokens.append(.op(String(c))); i += 1; continue
            }
            if c == "×" { tokens.append(.op("*")); i += 1; continue }
            if c == "÷" { tokens.append(.op("/")); i += 1; continue }
            if c == "≤" { tokens.append(.op("<=")); i += 1; continue }
            if c == "≥" { tokens.append(.op(">=")); i += 1; continue }
            if c == "≠" { tokens.append(.op("!=")); i += 1; continue }
            if "()[]{},.:?".contains(c) {
                tokens.append(.punct(c)); i += 1; continue
            }
            throw ExpressionError(message: "Unexpected character '\(c)'")
        }
        tokens.append(.eof)
        return tokens
    }
}

// MARK: - Parser

struct Parser {
    var tokens: [Token]
    var pos = 0

    init(tokens: [Token]) { self.tokens = tokens }

    var current: Token { tokens[pos] }
    mutating func advance() { if pos < tokens.count - 1 { pos += 1 } }

    mutating func expect(_ p: Character) throws {
        guard case .punct(let c) = current, c == p else { throw ExpressionError(message: "Expected '\(p)'") }
        advance()
    }

    func isPunct(_ p: Character) -> Bool { if case .punct(let c) = current { return c == p }; return false }
    func isOp(_ o: String) -> Bool { if case .op(let x) = current { return x == o }; return false }
    func isWord(_ w: String) -> Bool { if case .ident(let x) = current { return x.lowercased() == w }; return false }

    mutating func parse() throws -> ExprNode {
        let e = try parseTernary()
        guard case .eof = current else { throw ExpressionError(message: "Unexpected trailing input") }
        return e
    }

    mutating func parseTernary() throws -> ExprNode {
        let cond = try parseCoalesce()
        if isPunct("?") {
            advance()
            let a = try parseTernary()
            try expect(":")
            let b = try parseTernary()
            return .ternary(cond, a, b)
        }
        return cond
    }

    mutating func parseCoalesce() throws -> ExprNode {
        var lhs = try parseOr()
        while isOp("??") { advance(); lhs = .binary("??", lhs, try parseOr()) }
        return lhs
    }

    mutating func parseOr() throws -> ExprNode {
        var lhs = try parseAnd()
        while isOp("||") || isWord("or") { advance(); lhs = .binary("||", lhs, try parseAnd()) }
        return lhs
    }

    mutating func parseAnd() throws -> ExprNode {
        var lhs = try parseEquality()
        while isOp("&&") || isWord("and") { advance(); lhs = .binary("&&", lhs, try parseEquality()) }
        return lhs
    }

    mutating func parseEquality() throws -> ExprNode {
        var lhs = try parseComparison()
        while true {
            if isOp("==") || isOp("=") { advance(); lhs = .binary("==", lhs, try parseComparison()) }
            else if isOp("!=") { advance(); lhs = .binary("!=", lhs, try parseComparison()) }
            else if isWord("is") { advance(); if isWord("not") { advance(); lhs = .binary("!=", lhs, try parseComparison()) } else { lhs = .binary("==", lhs, try parseComparison()) } }
            else { break }
        }
        return lhs
    }

    mutating func parseComparison() throws -> ExprNode {
        var lhs = try parseAdditive()
        while true {
            if case .op(let o) = current, ["<", "<=", ">", ">="].contains(o) {
                advance(); lhs = .binary(o, lhs, try parseAdditive())
            } else if isWord("in") {
                advance(); lhs = .binary("in", lhs, try parseAdditive())
            } else if isWord("contains") {
                advance(); lhs = .binary("contains", lhs, try parseAdditive())
            } else { break }
        }
        return lhs
    }

    mutating func parseAdditive() throws -> ExprNode {
        var lhs = try parseMultiplicative()
        while case .op(let o) = current, o == "+" || o == "-" {
            advance(); lhs = .binary(o, lhs, try parseMultiplicative())
        }
        return lhs
    }

    mutating func parseMultiplicative() throws -> ExprNode {
        var lhs = try parseUnary()
        while case .op(let o) = current, o == "*" || o == "/" || o == "%" {
            advance(); lhs = .binary(o, lhs, try parseUnary())
        }
        return lhs
    }

    mutating func parseUnary() throws -> ExprNode {
        if isOp("!") || isWord("not") { advance(); return .unary("!", try parseUnary()) }
        if isOp("-") { advance(); return .unary("-", try parseUnary()) }
        if isOp("+") { advance(); return try parseUnary() }
        return try parsePostfix()
    }

    mutating func parseArgs() throws -> [ExprNode] {
        var args: [ExprNode] = []
        try expect("(")
        if isPunct(")") { advance(); return args }
        while true {
            args.append(try parseTernary())
            if isPunct(",") { advance(); continue }
            try expect(")")
            break
        }
        return args
    }

    mutating func parsePostfix() throws -> ExprNode {
        var e = try parsePrimary()
        while true {
            if isPunct(".") {
                advance()
                guard case .ident(let name) = current else {
                    if case .number(let n) = current { advance(); e = .index(e, .literal(.number(n))); continue }
                    throw ExpressionError(message: "Expected property name")
                }
                advance()
                if isPunct("(") { e = .method(e, name, try parseArgs()) } else { e = .member(e, name) }
            } else if isPunct("[") {
                advance()
                let idx = try parseTernary()
                try expect("]")
                e = .index(e, idx)
            } else { break }
        }
        return e
    }

    mutating func parsePrimary() throws -> ExprNode {
        switch current {
        case .number(let d): advance(); return .literal(.number(d))
        case .string(let s): advance(); return .literal(.string(s))
        case .ident(let name):
            advance()
            switch name.lowercased() {
            case "true", "yes": return .literal(.bool(true))
            case "false", "no": return .literal(.bool(false))
            case "null", "nil", "none": return .literal(.null)
            default: break
            }
            if isPunct("(") { return .call(name, try parseArgs()) }
            return .variable(name)
        case .punct("("):
            advance()
            let e = try parseTernary()
            try expect(")")
            return e
        case .punct("["):
            advance()
            var items: [ExprNode] = []
            if isPunct("]") { advance(); return .array(items) }
            while true {
                items.append(try parseTernary())
                if isPunct(",") { advance(); if isPunct("]") { advance(); break }; continue }
                try expect("]")
                break
            }
            return .array(items)
        case .punct("{"):
            advance()
            var keys: [String] = []
            var vals: [ExprNode] = []
            if isPunct("}") { advance(); return .object(keys, vals) }
            while true {
                let key: String
                switch current {
                case .string(let s): key = s
                case .ident(let s): key = s
                case .number(let d): key = Value.format(number: d)
                default: throw ExpressionError(message: "Expected object key")
                }
                advance()
                try expect(":")
                keys.append(key)
                vals.append(try parseTernary())
                if isPunct(",") { advance(); if isPunct("}") { advance(); break }; continue }
                try expect("}")
                break
            }
            return .object(keys, vals)
        default:
            throw ExpressionError(message: "Unexpected token")
        }
    }
}

// MARK: - Engine

public enum ExpressionEngine {
    /// Locale used for number/currency/date formatting. Tests pin this for determinism.
    public static var locale: Locale = Locale(identifier: "en_US")
    public static var defaultCurrency = "USD"

    private static var cache: [String: ExprNode] = [:]
    private static let cacheLock = NSLock()

    public static func parse(_ source: String) throws -> ExprNode {
        cacheLock.lock()
        if let hit = cache[source] { cacheLock.unlock(); return hit }
        cacheLock.unlock()
        var parser = Parser(tokens: try Lexer.tokenize(source))
        let node = try parser.parse()
        cacheLock.lock()
        if cache.count > 4000 { cache.removeAll() }
        cache[source] = node
        cacheLock.unlock()
        return node
    }

    /// Validates an expression and returns a readable error if it cannot be parsed.
    public static func validate(_ source: String) -> String? {
        do { _ = try parse(source); return nil } catch { return "\(error)" }
    }

    /// Evaluates an expression leniently: errors produce `.null` instead of throwing.
    public static func evaluate(_ source: String, scope: Scope) -> Value {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .null }
        guard let node = try? parse(trimmed) else {
            // Bare words that are not valid expressions behave like text.
            return .string(trimmed)
        }
        return eval(node, scope)
    }

    public static func eval(_ node: ExprNode, _ scope: Scope) -> Value {
        switch node {
        case .literal(let v): return v
        case .variable(let name):
            if let v = scope.lookup(name) { return v }
            switch name.lowercased() {
            case "now": return .string(isoFormatter.string(from: Date()))
            case "today": return .string(dayFormatter.string(from: Date()))
            case "pi": return .number(Double.pi)
            default: return .null
            }
        case .member(let base, let name):
            let b = eval(base, scope)
            if case .object(let o) = b, let v = o[name] { return v }
            return property(b, name)
        case .index(let base, let idx):
            let b = eval(base, scope)
            let i = eval(idx, scope)
            if case .number(let n) = i {
                var index = Int(n)
                if case .array(let a) = b, index < 0 { index += a.count }
                if case .string(let s) = b {
                    let chars = Array(s)
                    if index < 0 { index += chars.count }
                    return chars.indices.contains(index) ? .string(String(chars[index])) : .null
                }
                return b[index]
            }
            return b[i.stringValue]
        case .call(let name, let args):
            return call(name, args.map { eval($0, scope) })
        case .method(let base, let name, let args):
            let b = eval(base, scope)
            if case .object(let o) = b, let v = o[name], args.isEmpty { return v }
            return call(name, [b] + args.map { eval($0, scope) })
        case .unary(let op, let e):
            let v = eval(e, scope)
            if op == "!" { return .bool(!v.boolValue) }
            if op == "-" { return .number(-(v.numberValue ?? 0)) }
            return v
        case .binary(let op, let l, let r):
            if op == "&&" { let lv = eval(l, scope); return lv.boolValue ? .bool(eval(r, scope).boolValue) : .bool(false) }
            if op == "||" { let lv = eval(l, scope); return lv.boolValue ? .bool(true) : .bool(eval(r, scope).boolValue) }
            if op == "??" { let lv = eval(l, scope); return (lv.isNull || lv == .string("")) ? eval(r, scope) : lv }
            return binary(op, eval(l, scope), eval(r, scope))
        case .ternary(let c, let a, let b):
            return eval(c, scope).boolValue ? eval(a, scope) : eval(b, scope)
        case .array(let items):
            return .array(items.map { eval($0, scope) })
        case .object(let keys, let vals):
            var o: [String: Value] = [:]
            for (k, v) in zip(keys, vals) { o[k] = eval(v, scope) }
            return .object(o)
        }
    }

    // MARK: Operators

    static func bothNumeric(_ a: Value, _ b: Value) -> (Double, Double)? {
        func num(_ v: Value) -> Double? {
            switch v {
            case .number(let d): return d
            case .bool(let b): return b ? 1 : 0
            case .null: return nil
            case .string(let s):
                let t = s.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { return nil }
                return Value.parseNumber(t)
            default: return nil
            }
        }
        guard let x = num(a), let y = num(b) else { return nil }
        return (x, y)
    }

    static func binary(_ op: String, _ a: Value, _ b: Value) -> Value {
        switch op {
        case "+":
            if case .array(let x) = a { if case .array(let y) = b { return .array(x + y) }; return .array(x + [b]) }
            if let (x, y) = bothNumeric(a, b), !(a.isNull && b.isNull) {
                if case .string = a, case .string = b { return .number(x + y) }
                return .number(x + y)
            }
            if a.isNull, let y = b.numberValue, case .number = b { return .number(y) }
            if b.isNull, let x = a.numberValue, case .number = a { return .number(x) }
            return .string(a.stringValue + b.stringValue)
        case "-":
            if case .array(let x) = a { return .array(x.filter { $0 != b }) }
            return .number((a.numberValue ?? 0) - (b.numberValue ?? 0))
        case "*":
            if case .string(let s) = a, let n = b.numberValue, Value.parseNumber(s) == nil { return .string(String(repeating: s, count: max(0, Int(n)))) }
            return .number((a.numberValue ?? 0) * (b.numberValue ?? 0))
        case "/":
            let d = b.numberValue ?? 0
            if d == 0 { return .number(0) }
            return .number((a.numberValue ?? 0) / d)
        case "%":
            let d = b.numberValue ?? 0
            if d == 0 { return .number(0) }
            return .number((a.numberValue ?? 0).truncatingRemainder(dividingBy: d))
        case "==": return .bool(equals(a, b))
        case "!=": return .bool(!equals(a, b))
        case "<", "<=", ">", ">=":
            let c = compare(a, b)
            switch op {
            case "<": return .bool(c < 0)
            case "<=": return .bool(c <= 0)
            case ">": return .bool(c > 0)
            default: return .bool(c >= 0)
            }
        case "in": return .bool(contains(b, a))
        case "contains": return .bool(contains(a, b))
        default: return .null
        }
    }

    public static func equals(_ a: Value, _ b: Value) -> Bool {
        if a == b { return true }
        switch (a, b) {
        case (.null, .string(let s)), (.string(let s), .null): return s.isEmpty
        case (.bool(let x), _): return x == b.boolValue
        case (_, .bool(let y)): return a.boolValue == y
        default: break
        }
        if let (x, y) = bothNumeric(a, b) { return x == y }
        return a.stringValue.compare(b.stringValue, options: [.caseInsensitive]) == .orderedSame
    }

    static func compare(_ a: Value, _ b: Value) -> Int {
        if let (x, y) = bothNumeric(a, b) { return x < y ? -1 : (x > y ? 1 : 0) }
        if let da = parseDate(a), let db = parseDate(b) { return da < db ? -1 : (da > db ? 1 : 0) }
        let r = a.stringValue.localizedStandardCompare(b.stringValue)
        return r == .orderedAscending ? -1 : (r == .orderedDescending ? 1 : 0)
    }

    static func contains(_ container: Value, _ needle: Value) -> Bool {
        switch container {
        case .array(let items): return items.contains { equals($0, needle) }
        case .object(let o): return o[needle.stringValue] != nil
        case .string(let s): return s.range(of: needle.stringValue, options: [.caseInsensitive, .diacriticInsensitive]) != nil || needle.stringValue.isEmpty
        default: return false
        }
    }

    static func property(_ v: Value, _ name: String) -> Value {
        switch name.lowercased() {
        case "count", "length", "size": return call("count", [v])
        case "first": return call("first", [v])
        case "last": return call("last", [v])
        case "isempty": return .bool(isEmpty(v))
        case "isnotempty": return .bool(!isEmpty(v))
        case "upper", "uppercased": return call("upper", [v])
        case "lower", "lowercased": return call("lower", [v])
        case "trimmed": return call("trim", [v])
        case "keys": return .array(v.objectValue.keys.sorted().map { .string($0) })
        case "values": return .array(v.objectValue.keys.sorted().compactMap { v.objectValue[$0] })
        default: return .null
        }
    }

    static func isEmpty(_ v: Value) -> Bool {
        switch v {
        case .null: return true
        case .string(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let a): return a.isEmpty
        case .object(let o): return o.isEmpty
        default: return false
        }
    }

    // MARK: Functions

    public static let functionNames: [String] = [
        "len", "count", "sum", "avg", "min", "max", "round", "floor", "ceil", "abs", "sqrt", "pow", "clamp",
        "upper", "lower", "capitalize", "trim", "contains", "startsWith", "endsWith", "replace", "split", "join",
        "substring", "prefix", "suffix", "isEmpty", "isNotEmpty", "default", "if", "string", "number", "int", "bool", "json",
        "currency", "format", "percent", "compact", "now", "today", "formatDate", "daysBetween", "addDays",
        "first", "last", "item", "reverse", "sort", "filter", "map", "unique", "range", "random", "uuid", "pluralize",
        "countWhere", "find", "indexOf", "isEmail", "length", "not", "and", "or", "toggle",
    ]

    static func field(_ v: Value, _ f: Value?) -> Value {
        guard let f = f, !f.stringValue.isEmpty else { return v }
        return v.value(atPath: f.stringValue)
    }

    static func numbers(_ args: [Value]) -> [Double] {
        if args.count == 1, case .array(let a) = args[0] { return a.compactMap { $0.numberValue } }
        if args.count == 2, case .array(let a) = args[0], case .string = args[1] { return a.compactMap { field($0, args[1]).numberValue } }
        return args.compactMap { $0.numberValue }
    }

    public static func call(_ rawName: String, _ args: [Value]) -> Value {
        let name = rawName.lowercased()
        let a0 = args.first ?? .null
        let a1 = args.count > 1 ? args[1] : nil
        let a2 = args.count > 2 ? args[2] : nil
        switch name {
        case "len", "count", "length", "size":
            switch a0 {
            case .array(let a): return .number(Double(a.count))
            case .string(let s): return .number(Double(s.count))
            case .object(let o): return .number(Double(o.count))
            case .null: return .number(0)
            default: return .number(1)
            }
        case "sum": return .number(numbers(args).reduce(0, +))
        case "avg", "average", "mean":
            let n = numbers(args); return .number(n.isEmpty ? 0 : n.reduce(0, +) / Double(n.count))
        case "min": return numbers(args).min().map { .number($0) } ?? .null
        case "max": return numbers(args).max().map { .number($0) } ?? .null
        case "round":
            let x = a0.numberValue ?? 0
            let digits = Int(a1?.numberValue ?? 0)
            let p = pow(10.0, Double(digits))
            return .number((x * p).rounded() / p)
        case "floor": return .number((a0.numberValue ?? 0).rounded(.down))
        case "ceil": return .number((a0.numberValue ?? 0).rounded(.up))
        case "abs": return .number(abs(a0.numberValue ?? 0))
        case "sqrt": return .number(sqrt(max(0, a0.numberValue ?? 0)))
        case "pow": return .number(pow(a0.numberValue ?? 0, a1?.numberValue ?? 1))
        case "clamp":
            let x = a0.numberValue ?? 0, lo = a1?.numberValue ?? x, hi = a2?.numberValue ?? x
            return .number(min(max(x, lo), hi))
        case "upper", "uppercase": return .string(a0.stringValue.uppercased())
        case "lower", "lowercase": return .string(a0.stringValue.lowercased())
        case "capitalize", "title": return .string(a0.stringValue.capitalized)
        case "trim": return .string(a0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        case "contains", "includes": return .bool(contains(a0, a1 ?? .null))
        case "startswith": return .bool(a0.stringValue.lowercased().hasPrefix((a1?.stringValue ?? "").lowercased()))
        case "endswith": return .bool(a0.stringValue.lowercased().hasSuffix((a1?.stringValue ?? "").lowercased()))
        case "replace": return .string(a0.stringValue.replacingOccurrences(of: a1?.stringValue ?? "", with: a2?.stringValue ?? ""))
        case "split":
            let sep = a1?.stringValue ?? ","
            return .array(a0.stringValue.components(separatedBy: sep.isEmpty ? "," : sep).map { .string($0.trimmingCharacters(in: .whitespaces)) })
        case "join":
            let sep = a1?.stringValue ?? ", "
            return .string(a0.arrayValue.map { $0.stringValue }.joined(separator: sep))
        case "substring", "substr", "mid":
            let chars = Array(a0.stringValue)
            let start = max(0, min(chars.count, Int(a1?.numberValue ?? 0)))
            let len = a2.map { Int($0.numberValue ?? 0) } ?? (chars.count - start)
            let end = max(start, min(chars.count, start + max(0, len)))
            return .string(String(chars[start..<end]))
        case "prefix", "left": return .string(String(a0.stringValue.prefix(Int(a1?.numberValue ?? 1))))
        case "suffix", "right": return .string(String(a0.stringValue.suffix(Int(a1?.numberValue ?? 1))))
        case "isempty", "empty", "blank": return .bool(isEmpty(a0))
        case "isnotempty", "present": return .bool(!isEmpty(a0))
        case "default", "coalesce", "ifempty":
            for v in args where !isEmpty(v) { return v }
            return args.last ?? .null
        case "if", "iif": return a0.boolValue ? (a1 ?? .null) : (a2 ?? .null)
        case "not": return .bool(!a0.boolValue)
        case "and": return .bool(args.allSatisfy { $0.boolValue })
        case "or": return .bool(args.contains { $0.boolValue })
        case "toggle": return .bool(!a0.boolValue)
        case "string", "text", "str": return .string(a0.stringValue)
        case "number", "num", "float", "double": return .number(a0.numberValue ?? 0)
        case "int", "integer": return .number((a0.numberValue ?? 0).rounded(.towardZero))
        case "bool", "boolean": return .bool(a0.boolValue)
        case "json": return .string(a0.jsonString())
        case "parsejson": return Value.fromJSONString(a0.stringValue) ?? .null
        case "currency", "money":
            let code = a1?.stringValue.isEmpty == false ? a1!.stringValue : defaultCurrency
            return .string(formatCurrency(a0.numberValue ?? 0, code: code))
        case "format", "fixed", "decimal":
            let digits = Int(a1?.numberValue ?? 0)
            return .string(formatNumber(a0.numberValue ?? 0, digits: digits))
        case "percent", "percentage":
            let digits = Int(a1?.numberValue ?? 0)
            var v = a0.numberValue ?? 0
            if v > 1.0 && v <= 100 && a2?.boolValue != false { v /= 100 }
            return .string(formatNumber(v * 100, digits: digits) + "%")
        case "compact", "short":
            return .string(compactNumber(a0.numberValue ?? 0))
        case "now": return .string(isoFormatter.string(from: Date()))
        case "today": return .string(dayFormatter.string(from: Date()))
        case "formatdate", "date":
            guard let d = parseDate(a0) else { return .string(a0.stringValue) }
            return .string(formatDate(d, style: a1?.stringValue ?? "medium"))
        case "daysbetween":
            guard let x = parseDate(a0), let y = parseDate(a1 ?? .null) else { return .number(0) }
            return .number((y.timeIntervalSince(x) / 86400).rounded())
        case "adddays":
            guard let d = parseDate(a0) else { return .null }
            return .string(isoFormatter.string(from: d.addingTimeInterval((a1?.numberValue ?? 0) * 86400)))
        case "first": return a0.arrayValue.first ?? (a0.stringValue.first.map { .string(String($0)) } ?? .null)
        case "last": return a0.arrayValue.last ?? (a0.stringValue.last.map { .string(String($0)) } ?? .null)
        case "item", "at", "get":
            if case .array = a0 { return a0[Int(a1?.numberValue ?? 0)] }
            return a0.value(atPath: a1?.stringValue ?? "")
        case "reverse", "reversed":
            if case .string(let s) = a0 { return .string(String(s.reversed())) }
            return .array(a0.arrayValue.reversed())
        case "sort", "sorted":
            let items = a0.arrayValue
            let f = a1
            let desc = (a2?.stringValue.lowercased() == "desc") || (a1?.stringValue.lowercased() == "desc")
            let key: Value? = (f?.stringValue.lowercased() == "desc" || f?.stringValue.lowercased() == "asc") ? nil : f
            let sorted = items.sorted { compare(field($0, key), field($1, key)) < 0 }
            return .array(desc ? sorted.reversed() : sorted)
        case "filter", "where":
            let items = a0.arrayValue
            if let a2 = a2 { return .array(items.filter { equals(field($0, a1), a2) }) }
            if let a1 = a1 { return .array(items.filter { contains(.string($0.stringValue + " " + $0.objectValue.values.map { $0.stringValue }.joined(separator: " ")), a1) }) }
            return .array(items.filter { !isEmpty($0) })
        case "countwhere":
            let items = a0.arrayValue
            if let a2 = a2 { return .number(Double(items.filter { equals(field($0, a1), a2) }.count)) }
            return .number(Double(items.filter { field($0, a1).boolValue }.count))
        case "find":
            return a0.arrayValue.first { equals(field($0, a1), a2 ?? .null) } ?? .null
        case "indexof":
            if case .string(let s) = a0, let r = s.range(of: a1?.stringValue ?? "") { return .number(Double(s.distance(from: s.startIndex, to: r.lowerBound))) }
            return .number(Double(a0.arrayValue.firstIndex { equals($0, a1 ?? .null) } ?? -1))
        case "map", "pluck": return .array(a0.arrayValue.map { field($0, a1) })
        case "unique", "distinct":
            var seen: [Value] = []
            for v in a0.arrayValue where !seen.contains(v) { seen.append(v) }
            return .array(seen)
        case "range":
            let lo = Int(a1 == nil ? 0 : (a0.numberValue ?? 0)), hi = Int(a1?.numberValue ?? (a0.numberValue ?? 0))
            guard hi > lo, hi - lo < 10_000 else { return .array([]) }
            return .array((lo..<hi).map { .number(Double($0)) })
        case "random":
            let lo = a1 == nil ? 0 : (a0.numberValue ?? 0)
            let hi = a1?.numberValue ?? (a0.isNull ? 1 : (a0.numberValue ?? 1))
            if case .array(let items) = a0 { return items.randomElement() ?? .null }
            if hi <= lo { return .number(lo) }
            if lo == lo.rounded() && hi == hi.rounded() && !(a0.isNull) { return .number(Double(Int.random(in: Int(lo)...Int(hi)))) }
            return .number(Double.random(in: lo..<hi))
        case "uuid", "id": return .string(UUID().uuidString)
        case "pluralize", "plural":
            let n = a0.numberValue ?? 0
            let word = a1?.stringValue ?? "item"
            let plural = a2?.stringValue ?? (word.hasSuffix("s") ? word : word + "s")
            return .string("\(Value.format(number: n)) \(n == 1 ? word : plural)")
        case "isemail":
            let s = a0.stringValue
            let parts = s.split(separator: "@")
            return .bool(parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty && !s.contains(" "))
        default:
            return .null
        }
    }

    // MARK: Formatting

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func parseDate(_ v: Value) -> Date? {
        switch v {
        case .number(let d): return d > 1_000_000_000_000 ? Date(timeIntervalSince1970: d / 1000) : Date(timeIntervalSince1970: d)
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return nil }
            if let d = isoFormatter.date(from: t) ?? isoFractional.date(from: t) { return d }
            if let d = dayFormatter.date(from: String(t.prefix(10))), t.count >= 10, t.dropFirst(4).first == "-" { return d }
            return nil
        default: return nil
        }
    }

    public static func formatDate(_ d: Date, style: String) -> String {
        let f = DateFormatter()
        f.locale = locale
        switch style.lowercased() {
        case "short": f.dateStyle = .short; f.timeStyle = .none
        case "medium", "": f.dateStyle = .medium; f.timeStyle = .none
        case "long": f.dateStyle = .long; f.timeStyle = .none
        case "full": f.dateStyle = .full; f.timeStyle = .none
        case "time": f.dateStyle = .none; f.timeStyle = .short
        case "datetime", "both": f.dateStyle = .medium; f.timeStyle = .short
        case "weekday": f.dateFormat = "EEEE"
        case "month": f.dateFormat = "MMMM yyyy"
        case "relative":
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: d)).day ?? 0
            switch days {
            case 0: return "Today"
            case 1: return "Tomorrow"
            case -1: return "Yesterday"
            case 2...6: return "In \(days) days"
            case -6 ... -2: return "\(-days) days ago"
            default: f.dateStyle = .medium; f.timeStyle = .none
            }
        default: f.dateFormat = style
        }
        return f.string(from: d)
    }

    /// Grouped, fixed-digit formatting implemented by hand so results are identical on every platform.
    public static func formatNumber(_ v: Double, digits: Int) -> String {
        guard v.isFinite else { return Value.format(number: v) }
        let d = max(0, min(10, digits))
        let s = String(format: "%.\(d)f", abs(v))
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        let groupSep = locale.groupingSeparator ?? ","
        let decSep = locale.decimalSeparator ?? "."
        var grouped = ""
        for (i, ch) in String(parts[0]).reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped = groupSep + grouped }
            grouped = String(ch) + grouped
        }
        let negative = v < 0 && s.contains(where: { $0 != "0" && $0 != "." })
        return (negative ? "-" : "") + grouped + (d > 0 && parts.count > 1 ? decSep + parts[1] : "")
    }

    public static func formatCurrency(_ v: Double, code: String) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .currency
        f.currencyCode = code.uppercased()
        let wholeLarge = v == v.rounded() && abs(v) >= 1000
        f.minimumFractionDigits = wholeLarge ? 0 : 2
        f.maximumFractionDigits = wholeLarge ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "\(code) \(Value.format(number: v))"
    }

    public static func compactNumber(_ v: Double) -> String {
        let a = abs(v)
        let sign = v < 0 ? "-" : ""
        func trim(_ x: Double) -> String {
            let r = (x * 10).rounded() / 10
            return Value.format(number: r)
        }
        if a >= 1_000_000_000 { return sign + trim(a / 1_000_000_000) + "B" }
        if a >= 1_000_000 { return sign + trim(a / 1_000_000) + "M" }
        if a >= 1_000 { return sign + trim(a / 1_000) + "K" }
        return sign + trim(a)
    }
}

// MARK: - Templates ({{ expression }} interpolation)

public enum Template {
    public static func containsTemplate(_ s: String) -> Bool { s.contains("{{") && s.contains("}}") }

    /// Renders all `{{ expr }}` segments into a display string.
    public static func render(_ s: String, scope: Scope) -> String {
        guard containsTemplate(s) else { return s }
        var out = ""
        var rest = Substring(s)
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else { out += rest[open.lowerBound...]; return out }
            let expr = String(after[..<close.lowerBound])
            out += ExpressionEngine.evaluate(expr, scope: scope).stringValue
            rest = after[close.upperBound...]
        }
        out += rest
        return out
    }

    /// If the string is a single `{{ expr }}`, returns the typed value; otherwise the rendered string.
    public static func resolve(_ s: String, scope: Scope) -> Value {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("{{"), t.hasSuffix("}}") {
            let inner = String(t.dropFirst(2).dropLast(2))
            if !inner.contains("{{") && !inner.contains("}}") {
                return ExpressionEngine.evaluate(inner, scope: scope)
            }
        }
        return .string(render(s, scope: scope))
    }

    /// Resolves a property value: strings are interpolated, other values pass through.
    public static func resolve(_ v: Value, scope: Scope) -> Value {
        if case .string(let s) = v { return resolve(s, scope: scope) }
        if case .array(let items) = v { return .array(items.map { resolve($0, scope: scope) }) }
        return v
    }

    /// Variable names referenced in a template or expression (best effort; used for validation and the inspector).
    public static func referencedNames(in s: String) -> Set<String> {
        var names = Set<String>()
        var sources: [String] = []
        if containsTemplate(s) {
            var rest = Substring(s)
            while let open = rest.range(of: "{{"), let close = rest[open.upperBound...].range(of: "}}") {
                sources.append(String(rest[open.upperBound..<close.lowerBound]))
                rest = rest[close.upperBound...]
            }
        } else { sources = [s] }
        for src in sources {
            guard let node = try? ExpressionEngine.parse(src) else { continue }
            collect(node, &names)
        }
        return names
    }

    static func collect(_ n: ExprNode, _ names: inout Set<String>) {
        switch n {
        case .variable(let v): names.insert(v)
        case .member(let b, _): collect(b, &names)
        case .index(let b, let i): collect(b, &names); collect(i, &names)
        case .call(_, let args): args.forEach { collect($0, &names) }
        case .method(let b, _, let args): collect(b, &names); args.forEach { collect($0, &names) }
        case .unary(_, let e): collect(e, &names)
        case .binary(_, let l, let r): collect(l, &names); collect(r, &names)
        case .ternary(let c, let a, let b): collect(c, &names); collect(a, &names); collect(b, &names)
        case .array(let items): items.forEach { collect($0, &names) }
        case .object(_, let vals): vals.forEach { collect($0, &names) }
        case .literal: break
        }
    }
}
