import Foundation

/// ReyForge Script (RFS): a compact, line-based UI language that small on-device
/// models can write reliably (constrained by a GBNF grammar) and humans can read.
///
///     SCREEN "Dashboard" icon=chart.bar tab
///       TITLE "Good morning"
///       HSTACK
///         STAT "Balance" "$12,450" icon=creditcard
///       BUTTON "Add" icon=plus style=prominent -> sheet "Add Item"
public struct RFSLine: Hashable {
    public enum Kind: Hashable { case screen, app, variable, edit, delete, nav, say, component(String), end, comment }
    public var kind: Kind
    public var indent: Int
    public var positional: [String]
    public var attributes: [String: String]
    public var attributeOrder: [String]
    public var flags: [String]
    public var actions: String?
    /// Every token after the keyword, unclassified (quotes removed).
    public var tokens: [String]
    public var raw: String
    public var lineNumber: Int
}

public enum RFSParser {
    static let statementWords: [String: RFSLine.Kind] = [
        "SCREEN": .screen, "PAGE": .screen, "VIEW": .screen,
        "APP": .app, "THEME": .app, "BRAND": .app, "STYLE": .app,
        "VAR": .variable, "VARIABLE": .variable, "STATE": .variable,
        "EDIT": .edit, "UPDATE": .edit, "MODIFY": .edit, "CHANGE": .edit,
        "DELETE": .delete, "REMOVE": .delete,
        "NAV": .nav, "NAVIGATION": .nav,
        "SAY": .say, "REPLY": .say, "MESSAGE": .say,
        "END": .end, "DONE": .end,
    ]

    public static func parse(_ script: String) -> [RFSLine] {
        var out: [RFSLine] = []
        let normalized = script.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\t", with: "  ")
        for (n, rawLine) in normalized.components(separatedBy: "\n").enumerated() {
            var line = rawLine
            // Strip Markdown code fences and bullets the model may add.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("```") { continue }
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let lead = line.prefix(while: { $0 == " " })
                line = String(lead) + String(trimmed.dropFirst(2))
            }
            if let parsed = parseLine(line, number: n + 1) {
                if parsed.kind == .end { break }
                out.append(parsed)
            }
        }
        return out
    }

    public static func parseLine(_ line: String, number: Int = 0) -> RFSLine? {
        let spaces = line.prefix(while: { $0 == " " }).count
        let indent = spaces / 2
        let body = line.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        // Split off actions at the first top-level "->" (or "→").
        var head = body
        var actions: String?
        if let r = topLevelArrow(in: body) {
            head = String(body[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            actions = String(body[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        let tokens = tokenize(head)
        guard let first = tokens.first else { return nil }
        let keyword = first.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let kind: RFSLine.Kind
        if let k = statementWords[keyword] { kind = k }
        else if keyword.allSatisfy({ $0.isLetter }) { kind = .component(keyword) }
        else { return nil }

        var positional: [String] = []
        var attributes: [String: String] = [:]
        var order: [String] = []
        var flags: [String] = []
        for t in tokens.dropFirst() {
            if let eq = t.firstIndex(of: "="), !t.hasPrefix("\""), t.first != "[" && t.first != "{" {
                let key = String(t[..<eq]).trimmingCharacters(in: .whitespaces)
                var value = String(t[t.index(after: eq)...])
                value = unquote(value)
                if !key.isEmpty {
                    let k = key.lowercased()
                    if attributes[k] == nil { order.append(k) }
                    attributes[k] = value
                }
            } else if isQuoted(t) {
                positional.append(unquote(t))
            } else if t.first == "[" || t.first == "{" {
                positional.append(t)
            } else if t.first?.isLetter == true && t.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }) && !t.contains(".") && t.first?.isUppercase == false {
                flags.append(t.lowercased())
            } else {
                positional.append(t)
            }
        }
        return RFSLine(kind: kind, indent: indent, positional: positional, attributes: attributes, attributeOrder: order, flags: flags, actions: actions,
                       tokens: tokens.dropFirst().map { unquote($0) }, raw: line, lineNumber: number)
    }

    static func topLevelArrow(in s: String) -> Range<String.Index>? {
        var inQuote = false
        var depth = 0
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\"" || c == "“" || c == "”" { inQuote.toggle() }
            else if !inQuote {
                if c == "{" || c == "[" { depth += 1 }
                else if c == "}" || c == "]" { depth = max(0, depth - 1) }
                else if depth == 0 {
                    if c == "→" { return i..<s.index(after: i) }
                    if c == "-", s.index(after: i) < s.endIndex, s[s.index(after: i)] == ">" {
                        return i..<s.index(i, offsetBy: 2)
                    }
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    /// Splits on whitespace while keeping quoted strings and balanced JSON together.
    public static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var cur = ""
        var inQuote = false
        var depth = 0
        for c in s {
            if c == "“" || c == "”" {
                inQuote.toggle(); cur.append("\""); continue
            }
            if c == "\"" { inQuote.toggle(); cur.append(c); continue }
            if !inQuote {
                if c == "[" || c == "{" { depth += 1 }
                if c == "]" || c == "}" { depth = max(0, depth - 1) }
                if c == " " && depth == 0 {
                    if !cur.isEmpty { tokens.append(cur); cur = "" }
                    continue
                }
            }
            cur.append(c)
        }
        if !cur.isEmpty { tokens.append(cur) }
        return tokens
    }

    static func isQuoted(_ t: String) -> Bool { t.count >= 2 && t.hasPrefix("\"") && t.hasSuffix("\"") }

    static func unquote(_ t: String) -> String {
        var s = t
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") { s = String(s.dropFirst().dropLast()) }
        else if s.hasPrefix("\"") { s = String(s.dropFirst()) }
        return s.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n")
    }

    // MARK: Actions

    public struct ParsedAction: Hashable {
        public var verb: String
        public var args: [String]
        public var block: String?
        public var elseBlock: String?
    }

    /// Splits "inc count; haptic light; if count > 3 { toast "Big" } else { back }".
    public static func splitActions(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var inQuote = false
        var depth = 0
        for c in s {
            if c == "\"" || c == "“" || c == "”" { inQuote.toggle() }
            if !inQuote {
                if c == "{" || c == "[" { depth += 1 }
                if c == "}" || c == "]" { depth = max(0, depth - 1) }
                if c == ";" && depth == 0 {
                    let t = cur.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { parts.append(t) }
                    cur = ""
                    continue
                }
            }
            cur.append(c)
        }
        let t = cur.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { parts.append(t) }
        return parts
    }

    public static func parseAction(_ s: String) -> ParsedAction? {
        var text = s.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        var block: String?
        var elseBlock: String?
        // Extract { ... } blocks for if/confirm.
        if let open = text.firstIndex(of: "{"), let close = matchingBrace(text, from: open) {
            block = String(text[text.index(after: open)..<close])
            var rest = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            if rest.lowercased().hasPrefix("else") {
                rest = String(rest.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if let eo = rest.firstIndex(of: "{"), let ec = matchingBrace(rest, from: eo) {
                    elseBlock = String(rest[rest.index(after: eo)..<ec])
                } else if !rest.isEmpty {
                    elseBlock = rest
                }
            }
            text = String(text[..<open]).trimmingCharacters(in: .whitespaces)
            if text.lowercased().hasSuffix(" then") { text = String(text.dropLast(5)) }
        }
        let tokens = tokenize(text)
        guard let verb = tokens.first?.lowercased() else { return nil }
        return ParsedAction(verb: verb, args: Array(tokens.dropFirst()), block: block, elseBlock: elseBlock)
    }

    static func matchingBrace(_ s: String, from open: String.Index) -> String.Index? {
        var depth = 0
        var inQuote = false
        var i = open
        while i < s.endIndex {
            let c = s[i]
            if c == "\"" { inQuote.toggle() }
            if !inQuote {
                if c == "{" { depth += 1 }
                if c == "}" { depth -= 1; if depth == 0 { return i } }
            }
            i = s.index(after: i)
        }
        return nil
    }
}
