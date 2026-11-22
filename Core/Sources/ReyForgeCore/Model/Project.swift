import Foundation

// MARK: - Decoding helpers

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback()
    }
    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

public enum IDGen {
    private static let alphabet = Array("abcdefghijkmnopqrstuvwxyz23456789")
    /// Short, readable identifiers such as "n7k2pq9d" — easy to reference from ReyForge Script.
    public static func short(_ prefix: String = "", length: Int = 8) -> String {
        var g = SystemRandomNumberGenerator()
        return prefix + String((0..<length).map { _ in alphabet[Int(g.next() % UInt64(alphabet.count))] })
    }
}

// MARK: - Project

public struct Project: Codable, Identifiable, Hashable {
    public static let currentSchema = 3

    public var schema: Int
    public var id: UUID
    public var name: String
    public var bundleID: String
    public var version: String
    public var build: Int
    public var brand: Brand
    public var theme: Theme
    public var navigation: NavigationConfig
    public var screens: [Screen]
    public var variables: [Variable]
    public var apis: [APIEndpoint]
    public var widget: WidgetConfig
    public var templateID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, bundleID: String? = nil, version: String = "1.0", build: Int = 1,
                brand: Brand? = nil, theme: Theme = Theme(), navigation: NavigationConfig = NavigationConfig(),
                screens: [Screen] = [], variables: [Variable] = [], apis: [APIEndpoint] = [],
                widget: WidgetConfig = WidgetConfig(), templateID: String? = nil) {
        self.schema = Project.currentSchema
        self.id = id
        self.name = name
        self.bundleID = bundleID ?? BundleID.suggest(for: name)
        self.version = version
        self.build = build
        self.brand = brand ?? Brand(displayName: name)
        self.theme = theme
        self.navigation = navigation
        self.screens = screens
        self.variables = variables
        self.apis = apis
        self.widget = widget
        self.templateID = templateID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case schema, id, name, bundleID, version, build, brand, theme, navigation, screens, variables, apis, widget, templateID, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = c.value(.schema, Project.currentSchema)
        id = c.value(.id, UUID())
        name = c.value(.name, "Untitled")
        bundleID = c.value(.bundleID, BundleID.suggest(for: name))
        version = c.value(.version, "1.0")
        build = c.value(.build, 1)
        brand = c.value(.brand, Brand(displayName: name))
        theme = c.value(.theme, Theme())
        navigation = c.value(.navigation, NavigationConfig())
        screens = c.value(.screens, [])
        variables = c.value(.variables, [])
        apis = c.value(.apis, [])
        widget = c.value(.widget, WidgetConfig())
        templateID = c.optional(.templateID)
        createdAt = c.value(.createdAt, Date())
        updatedAt = c.value(.updatedAt, Date())
    }

    // MARK: JSON

    public static func makeEncoder(pretty: Bool = true) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                if let date = ExpressionEngine.isoFormatter.date(from: s) ?? ExpressionEngine.isoFractional.date(from: s) { return date }
            }
            if let t = try? c.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: t) }
            return Date()
        }
        return d
    }

    public func jsonData(pretty: Bool = true) throws -> Data {
        try Project.makeEncoder(pretty: pretty).encode(self)
    }

    public static func decode(_ data: Data) throws -> Project {
        var p = try makeDecoder().decode(Project.self, from: data)
        p.normalize()
        return p
    }

    /// Repairs references so the project is always renderable (unique ids, valid tabs, initial screen).
    public mutating func normalize() {
        schema = Project.currentSchema
        var seen = Set<String>()
        for i in screens.indices {
            if screens[i].id.isEmpty || seen.contains(screens[i].id) { screens[i].id = IDGen.short("s") }
            seen.insert(screens[i].id)
            screens[i].root.repairIDs(&seen)
        }
        let ids = Set(screens.map { $0.id })
        navigation.tabs.removeAll { !ids.contains($0.screenID) }
        if let initial = navigation.initialScreenID, !ids.contains(initial) { navigation.initialScreenID = nil }
        if navigation.initialScreenID == nil { navigation.initialScreenID = navigation.tabs.first?.screenID ?? screens.first?.id }
        if navigation.style == .tabs && navigation.tabs.isEmpty { navigation.style = .stack }
        var names = Set<String>()
        variables.removeAll { v in
            let key = v.name.lowercased()
            if v.name.isEmpty || names.contains(key) { return true }
            names.insert(key)
            return false
        }
    }
}

// MARK: - Bundle identifiers

public enum BundleID {
    public static func slug(_ s: String) -> String {
        let lowered = s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        for ch in lowered {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { out.append(ch) }
        }
        if out.isEmpty { out = "app" }
        if let f = out.first, f.isNumber { out = "app" + out }
        return String(out.prefix(40))
    }

    public static func suggest(for name: String, prefix: String = "com.reyforge") -> String {
        "\(prefix).\(slug(name))"
    }

    /// A valid iOS bundle identifier: reverse-DNS, letters/numbers/hyphens/dots, at least two segments.
    public static func isValid(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, id.count <= 155 else { return false }
        for p in parts {
            if p.isEmpty { return false }
            for ch in p where !(ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-")) { return false }
        }
        return true
    }

    /// Whether a provisioning profile application-identifier pattern (e.g. "TEAMID.com.foo.*") permits a bundle id.
    public static func matches(pattern: String, bundleID: String) -> Bool {
        var p = pattern
        if let dot = p.firstIndex(of: "."), p[..<dot].count == 10, p[..<dot].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            p = String(p[p.index(after: dot)...])
        }
        if p == "*" { return true }
        if p.hasSuffix(".*") { return bundleID.hasPrefix(String(p.dropLast(1))) || bundleID == String(p.dropLast(2)) }
        if p.hasSuffix("*") { return bundleID.hasPrefix(String(p.dropLast())) }
        return p == bundleID
    }
}

// MARK: - Screen

public struct Screen: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var title: String
    public var icon: String
    public var showsNavigationBar: Bool
    public var largeTitle: Bool
    public var scrolls: Bool
    public var background: Fill?
    public var root: Node
    public var onAppear: [Action]
    public var toolbar: [ScreenToolbarItem]
    public var searchBinding: String?
    public var refreshActions: [Action]
    public var notes: String

    public init(id: String = IDGen.short("s"), name: String, title: String? = nil, icon: String = "square.grid.2x2",
                showsNavigationBar: Bool = true, largeTitle: Bool = true, scrolls: Bool = true,
                background: Fill? = nil, root: Node? = nil, children: [Node] = [], onAppear: [Action] = [],
                toolbar: [ScreenToolbarItem] = [], searchBinding: String? = nil, refreshActions: [Action] = []) {
        self.id = id
        self.name = name
        self.title = title ?? name
        self.icon = icon
        self.showsNavigationBar = showsNavigationBar
        self.largeTitle = largeTitle
        self.scrolls = scrolls
        self.background = background
        var r = root ?? Node.screenRoot()
        if root == nil { r.children = children }
        self.root = r
        self.onAppear = onAppear
        self.toolbar = toolbar
        self.searchBinding = searchBinding
        self.refreshActions = refreshActions
        self.notes = ""
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title, icon, showsNavigationBar, largeTitle, scrolls, background, root, onAppear, toolbar, searchBinding, refreshActions, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, IDGen.short("s"))
        name = c.value(.name, "Screen")
        title = c.value(.title, name)
        icon = c.value(.icon, "square.grid.2x2")
        showsNavigationBar = c.value(.showsNavigationBar, true)
        largeTitle = c.value(.largeTitle, true)
        scrolls = c.value(.scrolls, true)
        background = c.optional(.background)
        root = c.value(.root, Node.screenRoot())
        onAppear = c.value(.onAppear, [])
        toolbar = c.value(.toolbar, [])
        searchBinding = c.optional(.searchBinding)
        refreshActions = c.value(.refreshActions, [])
        notes = c.value(.notes, "")
    }
}

public struct ScreenToolbarItem: Codable, Hashable, Identifiable {
    public enum Placement: String, Codable, CaseIterable { case leading, trailing, bottom }
    public var id: String
    public var placement: Placement
    public var title: String
    public var icon: String
    public var actions: [Action]

    public init(id: String = IDGen.short("t"), placement: Placement = .trailing, title: String = "", icon: String = "plus", actions: [Action] = []) {
        self.id = id
        self.placement = placement
        self.title = title
        self.icon = icon
        self.actions = actions
    }

    enum CodingKeys: String, CodingKey { case id, placement, title, icon, actions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, IDGen.short("t"))
        placement = c.value(.placement, .trailing)
        title = c.value(.title, "")
        icon = c.value(.icon, "")
        actions = c.value(.actions, [])
    }
}

// MARK: - Node (a component instance)

public struct Node: Codable, Identifiable, Hashable {
    public var id: String
    public var type: ComponentType
    public var name: String?
    public var props: [String: Value]
    public var style: Style
    public var children: [Node]
    public var events: [EventHandler]
    public var binding: String?
    public var repeatSource: String?
    public var visibleIf: String?
    public var locked: Bool

    public init(id: String = IDGen.short("n"), type: ComponentType, name: String? = nil, props: [String: Value] = [:],
                style: Style = Style(), children: [Node] = [], events: [EventHandler] = [], binding: String? = nil,
                repeatSource: String? = nil, visibleIf: String? = nil, locked: Bool = false) {
        self.id = id
        self.type = type
        self.name = name
        self.props = props
        self.style = style
        self.children = children
        self.events = events
        self.binding = binding
        self.repeatSource = repeatSource
        self.visibleIf = visibleIf
        self.locked = locked
    }

    enum CodingKeys: String, CodingKey { case id, type, name, props, style, children, events, binding, repeatSource, visibleIf, locked }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, IDGen.short("n"))
        type = c.value(.type, .text)
        name = c.optional(.name)
        props = c.value(.props, [:])
        style = c.value(.style, Style())
        children = c.value(.children, [])
        events = c.value(.events, [])
        binding = c.optional(.binding)
        repeatSource = c.optional(.repeatSource)
        visibleIf = c.optional(.visibleIf)
        locked = c.value(.locked, false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(name, forKey: .name)
        if !props.isEmpty { try c.encode(props, forKey: .props) }
        if style != Style() { try c.encode(style, forKey: .style) }
        if !children.isEmpty { try c.encode(children, forKey: .children) }
        if !events.isEmpty { try c.encode(events, forKey: .events) }
        try c.encodeIfPresent(binding, forKey: .binding)
        try c.encodeIfPresent(repeatSource, forKey: .repeatSource)
        try c.encodeIfPresent(visibleIf, forKey: .visibleIf)
        if locked { try c.encode(locked, forKey: .locked) }
    }

    /// The default root container of a screen: a vertical stack with comfortable padding.
    public static func screenRoot() -> Node {
        Node(id: IDGen.short("r"), type: .vstack, name: "Screen", props: ["spacing": 16, "alignment": "leading"],
             style: Style(padding: Insets(all: 16)))
    }

    // MARK: Property helpers

    public func prop(_ key: String) -> Value { props[key] ?? ComponentRegistry.spec(for: type).defaultValue(for: key) }
    public func string(_ key: String) -> String { prop(key).stringValue }
    public func number(_ key: String) -> Double? { prop(key).numberValue }
    public func bool(_ key: String) -> Bool { prop(key).boolValue }

    public var displayName: String {
        if let n = name, !n.isEmpty { return n }
        let spec = ComponentRegistry.spec(for: type)
        for key in ["text", "title", "label", "placeholder"] {
            if let v = props[key]?.stringValue, !v.isEmpty {
                let short = v.count > 24 ? String(v.prefix(24)) + "…" : v
                return "\(spec.title) “\(short)”"
            }
        }
        return spec.title
    }

    public func handlers(for event: EventKind) -> [Action] {
        events.filter { $0.event == event }.flatMap { $0.actions }
    }

    public mutating func addAction(_ action: Action, on event: EventKind) {
        if let i = events.firstIndex(where: { $0.event == event }) {
            events[i].actions.append(action)
        } else {
            events.append(EventHandler(event: event, actions: [action]))
        }
    }

    mutating func repairIDs(_ seen: inout Set<String>) {
        if id.isEmpty || seen.contains(id) { id = IDGen.short("n") }
        seen.insert(id)
        for i in children.indices { children[i].repairIDs(&seen) }
    }

    /// Returns a deep copy with fresh identifiers (used by duplicate / paste / templates).
    public func clonedWithNewIDs() -> Node {
        var copy = self
        copy.id = IDGen.short("n")
        copy.events = events.map { $0.clonedWithNewIDs() }
        copy.children = children.map { $0.clonedWithNewIDs() }
        return copy
    }

    /// Depth-first list of this node and all descendants.
    public var flattened: [Node] {
        var out = [self]
        for c in children { out += c.flattened }
        return out
    }
}

// MARK: - Style

public enum SizeDimension: Codable, Hashable {
    case fill
    case fixed(Double)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .fixed(d); return }
        if let s = try? c.decode(String.self) {
            if s.lowercased() == "fill" || s == "100%" || s.lowercased() == "full" || s.lowercased() == "infinity" { self = .fill; return }
            if let d = Value.parseNumber(s) { self = .fixed(d); return }
        }
        self = .fill
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .fill: try c.encode("fill")
        case .fixed(let d): try c.encode(d)
        }
    }

    public var fixedValue: Double? { if case .fixed(let d) = self { return d }; return nil }
}

public struct Insets: Codable, Hashable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public init(all: Double) { self.init(top: all, leading: all, bottom: all, trailing: all) }
    public init(horizontal: Double, vertical: Double) { self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal) }

    public var isUniform: Bool { top == leading && leading == bottom && bottom == trailing }

    enum CodingKeys: String, CodingKey { case top, leading, bottom, trailing }
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let d = try? single.decode(Double.self) {
            self.init(all: d); return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(top: c.value(.top, 0), leading: c.value(.leading, 0), bottom: c.value(.bottom, 0), trailing: c.value(.trailing, 0))
    }
    public func encode(to encoder: Encoder) throws {
        if isUniform { var c = encoder.singleValueContainer(); try c.encode(top); return }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(top, forKey: .top); try c.encode(leading, forKey: .leading)
        try c.encode(bottom, forKey: .bottom); try c.encode(trailing, forKey: .trailing)
    }
}

/// A solid color or a gradient. Colors are hex strings ("#RRGGBB[AA]") or theme tokens ("accent", "surface"…).
public struct Fill: Codable, Hashable {
    public enum Kind: String, Codable, CaseIterable { case solid, linear, radial, angular }
    public var kind: Kind
    public var colors: [String]
    public var angle: Double

    public init(kind: Kind = .solid, colors: [String], angle: Double = 135) {
        self.kind = kind; self.colors = colors.isEmpty ? ["accent"] : colors; self.angle = angle
    }
    public static func solid(_ c: String) -> Fill { Fill(kind: .solid, colors: [c]) }
    public static func linear(_ colors: [String], angle: Double = 135) -> Fill { Fill(kind: .linear, colors: colors, angle: angle) }

    public var primaryColor: String { colors.first ?? "accent" }

    enum CodingKeys: String, CodingKey { case kind, colors, angle }
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            self.init(kind: parts.count > 1 ? .linear : .solid, colors: parts)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let colors: [String] = c.value(.colors, ["accent"])
        self.init(kind: c.value(.kind, colors.count > 1 ? .linear : .solid), colors: colors, angle: c.value(.angle, 135))
    }
    public func encode(to encoder: Encoder) throws {
        if kind == .solid && colors.count == 1 { var c = encoder.singleValueContainer(); try c.encode(colors[0]); return }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind); try c.encode(colors, forKey: .colors); try c.encode(angle, forKey: .angle)
    }
}

public struct FontSpec: Codable, Hashable {
    public var style: String?      // largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
    public var size: Double?
    public var weight: String?     // ultraLight … black
    public var design: String?     // default, rounded, serif, monospaced
    public var italic: Bool?

    public init(style: String? = nil, size: Double? = nil, weight: String? = nil, design: String? = nil, italic: Bool? = nil) {
        self.style = style; self.size = size; self.weight = weight; self.design = design; self.italic = italic
    }

    public static let textStyles = ["largeTitle", "title", "title2", "title3", "headline", "subheadline", "body", "callout", "footnote", "caption", "caption2"]
    public static let weights = ["ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"]
    public static let designs = ["default", "rounded", "serif", "monospaced"]

    /// Approximate point size of a Dynamic Type style (used by code generation and the icon renderer).
    public static func pointSize(for style: String) -> Double {
        switch style {
        case "largeTitle": return 34
        case "title": return 28
        case "title2": return 22
        case "title3": return 20
        case "headline", "body": return 17
        case "callout": return 16
        case "subheadline": return 15
        case "footnote": return 13
        case "caption": return 12
        case "caption2": return 11
        default: return 17
        }
    }
}

public struct ShadowSpec: Codable, Hashable {
    public var color: String
    public var radius: Double
    public var x: Double
    public var y: Double

    public init(color: String = "#00000026", radius: Double = 8, x: Double = 0, y: Double = 4) {
        self.color = color; self.radius = radius; self.x = x; self.y = y
    }
    public static let small = ShadowSpec(color: "#0000001A", radius: 4, x: 0, y: 2)
    public static let medium = ShadowSpec(color: "#00000026", radius: 10, x: 0, y: 5)
    public static let large = ShadowSpec(color: "#00000033", radius: 20, x: 0, y: 10)

    enum CodingKeys: String, CodingKey { case color, radius, x, y }
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            switch s.lowercased() {
            case "small", "sm": self = .small
            case "large", "lg": self = .large
            default: self = .medium
            }
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = c.value(.color, "#00000026"); radius = c.value(.radius, 8); x = c.value(.x, 0); y = c.value(.y, 4)
    }
}

public enum HAlign: String, Codable, CaseIterable { case leading, center, trailing }
public enum ClipShape: String, Codable, CaseIterable { case none, rounded, circle, capsule }

public struct Style: Codable, Hashable {
    public var width: SizeDimension?
    public var height: SizeDimension?
    public var minHeight: Double?
    public var maxWidth: Double?
    public var padding: Insets?
    public var margin: Insets?
    public var alignment: HAlign?
    public var offsetX: Double?
    public var offsetY: Double?
    public var background: Fill?
    public var foreground: String?
    public var font: FontSpec?
    public var cornerRadius: Double?
    public var borderColor: String?
    public var borderWidth: Double?
    public var shadow: ShadowSpec?
    public var opacity: Double?
    public var rotation: Double?
    public var scale: Double?
    public var clip: ClipShape?
    public var zIndex: Double?
    public var glass: Bool?
    public var aspectRatio: Double?
    public var blur: Double?

    public init(width: SizeDimension? = nil, height: SizeDimension? = nil, minHeight: Double? = nil, maxWidth: Double? = nil,
                padding: Insets? = nil, margin: Insets? = nil, alignment: HAlign? = nil, offsetX: Double? = nil, offsetY: Double? = nil,
                background: Fill? = nil, foreground: String? = nil, font: FontSpec? = nil, cornerRadius: Double? = nil,
                borderColor: String? = nil, borderWidth: Double? = nil, shadow: ShadowSpec? = nil, opacity: Double? = nil,
                rotation: Double? = nil, scale: Double? = nil, clip: ClipShape? = nil, zIndex: Double? = nil, glass: Bool? = nil,
                aspectRatio: Double? = nil, blur: Double? = nil) {
        self.width = width; self.height = height; self.minHeight = minHeight; self.maxWidth = maxWidth
        self.padding = padding; self.margin = margin; self.alignment = alignment; self.offsetX = offsetX; self.offsetY = offsetY
        self.background = background; self.foreground = foreground; self.font = font; self.cornerRadius = cornerRadius
        self.borderColor = borderColor; self.borderWidth = borderWidth; self.shadow = shadow; self.opacity = opacity
        self.rotation = rotation; self.scale = scale; self.clip = clip; self.zIndex = zIndex; self.glass = glass
        self.aspectRatio = aspectRatio; self.blur = blur
    }

    enum CodingKeys: String, CodingKey {
        case width, height, minHeight, maxWidth, padding, margin, alignment, offsetX, offsetY, background, foreground, font,
             cornerRadius, borderColor, borderWidth, shadow, opacity, rotation, scale, clip, zIndex, glass, aspectRatio, blur
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.optional(.width); height = c.optional(.height); minHeight = c.optional(.minHeight); maxWidth = c.optional(.maxWidth)
        padding = c.optional(.padding); margin = c.optional(.margin); alignment = c.optional(.alignment)
        offsetX = c.optional(.offsetX); offsetY = c.optional(.offsetY); background = c.optional(.background)
        foreground = c.optional(.foreground); font = c.optional(.font); cornerRadius = c.optional(.cornerRadius)
        borderColor = c.optional(.borderColor); borderWidth = c.optional(.borderWidth); shadow = c.optional(.shadow)
        opacity = c.optional(.opacity); rotation = c.optional(.rotation); scale = c.optional(.scale); clip = c.optional(.clip)
        zIndex = c.optional(.zIndex); glass = c.optional(.glass); aspectRatio = c.optional(.aspectRatio); blur = c.optional(.blur)
    }
}

// MARK: - Navigation

public struct NavigationConfig: Codable, Hashable {
    public enum Style: String, Codable, CaseIterable { case stack, tabs }
    public var style: Style
    public var initialScreenID: String?
    public var tabs: [TabItem]

    public init(style: Style = .stack, initialScreenID: String? = nil, tabs: [TabItem] = []) {
        self.style = style; self.initialScreenID = initialScreenID; self.tabs = tabs
    }

    enum CodingKeys: String, CodingKey { case style, initialScreenID, tabs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = c.value(.style, .stack); initialScreenID = c.optional(.initialScreenID); tabs = c.value(.tabs, [])
    }
}

public struct TabItem: Codable, Hashable, Identifiable {
    public var id: String { screenID }
    public var screenID: String
    public var title: String
    public var icon: String
    public init(screenID: String, title: String, icon: String) { self.screenID = screenID; self.title = title; self.icon = icon }
}

// MARK: - Variables & APIs

public struct Variable: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var type: ValueKind
    public var initial: Value
    public var persist: Bool
    public var formula: String?
    public var notes: String

    public init(id: String = IDGen.short("v"), name: String, type: ValueKind, initial: Value? = nil, persist: Bool = false, formula: String? = nil, notes: String = "") {
        self.id = id
        self.name = name
        self.type = type
        self.initial = initial.map { type.coerce($0) } ?? type.defaultValue
        self.persist = persist
        self.formula = formula
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey { case id, name, type, initial, persist, formula, notes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, IDGen.short("v"))
        name = c.value(.name, "value")
        type = c.value(.type, .text)
        initial = c.value(.initial, type.defaultValue)
        persist = c.value(.persist, false)
        formula = c.optional(.formula)
        notes = c.value(.notes, "")
    }

    public var isComputed: Bool { !(formula ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    /// Variable names must be valid expression identifiers.
    public static func sanitize(_ raw: String) -> String {
        var out = ""
        var upperNext = false
        for ch in raw {
            if ch.isLetter || ch.isNumber || ch == "_" {
                out.append(upperNext && !out.isEmpty ? Character(ch.uppercased()) : ch)
                upperNext = false
            } else { upperNext = true }
        }
        if out.isEmpty { out = "value" }
        if let f = out.first, f.isNumber { out = "v" + out }
        if let f = out.first, f.isUppercase { out = f.lowercased() + out.dropFirst() }
        return out
    }
}

public struct APIEndpoint: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: String
    public var resultVariable: String?
    public var resultPath: String

    public init(id: String = IDGen.short("a"), name: String, method: String = "GET", url: String, headers: [String: String] = [:],
                body: String = "", resultVariable: String? = nil, resultPath: String = "") {
        self.id = id; self.name = name; self.method = method; self.url = url; self.headers = headers
        self.body = body; self.resultVariable = resultVariable; self.resultPath = resultPath
    }

    enum CodingKeys: String, CodingKey { case id, name, method, url, headers, body, resultVariable, resultPath }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, IDGen.short("a")); name = c.value(.name, "API"); method = c.value(.method, "GET")
        url = c.value(.url, ""); headers = c.value(.headers, [:]); body = c.value(.body, "")
        resultVariable = c.optional(.resultVariable); resultPath = c.value(.resultPath, "")
    }
}

// MARK: - Widget

public struct WidgetConfig: Codable, Hashable {
    public enum Family: String, Codable, CaseIterable { case small, medium, large }
    public enum Layout: String, Codable, CaseIterable { case stat, list, quote, progress }
    public var enabled: Bool
    public var name: String
    public var summary: String
    public var family: Family
    public var layout: Layout
    public var title: String
    public var subtitle: String
    public var value: String
    public var symbol: String
    public var background: Fill
    public var foreground: String
    public var progress: Double
    public var items: [String]
    public var deepLinkScreenID: String?

    public init(enabled: Bool = false, name: String = "Widget", summary: String = "Glance at your app from the Home Screen.",
                family: Family = .small, layout: Layout = .stat, title: String = "Today", subtitle: String = "Updated just now",
                value: String = "42", symbol: String = "sparkles", background: Fill = .linear(["accent", "secondary"]),
                foreground: String = "#FFFFFF", progress: Double = 0.6, items: [String] = [], deepLinkScreenID: String? = nil) {
        self.enabled = enabled; self.name = name; self.summary = summary; self.family = family; self.layout = layout
        self.title = title; self.subtitle = subtitle; self.value = value; self.symbol = symbol; self.background = background
        self.foreground = foreground; self.progress = progress; self.items = items; self.deepLinkScreenID = deepLinkScreenID
    }

    enum CodingKeys: String, CodingKey { case enabled, name, summary, family, layout, title, subtitle, value, symbol, background, foreground, progress, items, deepLinkScreenID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WidgetConfig()
        enabled = c.value(.enabled, d.enabled); name = c.value(.name, d.name); summary = c.value(.summary, d.summary)
        family = c.value(.family, d.family); layout = c.value(.layout, d.layout); title = c.value(.title, d.title)
        subtitle = c.value(.subtitle, d.subtitle); value = c.value(.value, d.value); symbol = c.value(.symbol, d.symbol)
        background = c.value(.background, d.background); foreground = c.value(.foreground, d.foreground)
        progress = c.value(.progress, d.progress); items = c.value(.items, d.items); deepLinkScreenID = c.optional(.deepLinkScreenID)
    }
}
