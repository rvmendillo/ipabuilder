import Foundation

/// Where the user is in the editor; the AI uses it to resolve "this", "here" and "selected".
public struct EditorContext: Hashable {
    public var screenID: String?
    public var selectedNodeID: String?
    public var lastTouchedNodeIDs: [String]
    public init(screenID: String? = nil, selectedNodeID: String? = nil, lastTouchedNodeIDs: [String] = []) {
        self.screenID = screenID; self.selectedNodeID = selectedNodeID; self.lastTouchedNodeIDs = lastTouchedNodeIDs
    }
}

public struct ChangeRecord: Hashable {
    public enum Kind: String, Hashable { case addedScreen, updatedScreen, addedNode, updatedNode, removedNode, theme, brand, variable, navigation, logic }
    public var kind: Kind
    public var summary: String
    public var screenID: String?
    public var nodeID: String?
    public init(_ kind: Kind, _ summary: String, screenID: String? = nil, nodeID: String? = nil) {
        self.kind = kind; self.summary = summary; self.screenID = screenID; self.nodeID = nodeID
    }
}

public struct CompileResult {
    public var project: Project
    public var changes: [ChangeRecord]
    public var warnings: [String]
    public var reply: String?
    public var createdNodeIDs: [String]
    public var focusScreenID: String?
    public var focusNodeID: String?
    public var isEmpty: Bool { changes.isEmpty }
}

public struct RFSCompiler {
    var project: Project
    let context: EditorContext
    var changes: [ChangeRecord] = []
    var warnings: [String] = []
    var reply: String?
    var created: [String] = []
    var currentScreenIndex: Int?
    var screenOpenedByScript = false
    var stack: [(indent: Int, id: String)] = []
    var insertAfterID: String?
    var lastNodeID: String?
    var createdContainers: Set<String> = []
    var focusScreenID: String?

    public static func compile(_ script: String, into project: Project, context: EditorContext = EditorContext()) -> CompileResult {
        var c = RFSCompiler(project: project, context: context)
        c.run(RFSParser.parse(script))
        return c.result
    }

    init(project: Project, context: EditorContext) {
        self.project = project
        self.context = context
        if let sid = context.screenID, let i = project.screenIndex(id: sid) { currentScreenIndex = i }
    }

    var result: CompileResult {
        var p = project
        p.normalize()
        return CompileResult(project: p, changes: changes, warnings: warnings, reply: reply, createdNodeIDs: created,
                             focusScreenID: focusScreenID ?? currentScreenIndex.map { project.screens[$0].id }, focusNodeID: created.first ?? lastNodeID)
    }

    // MARK: Driver

    mutating func run(_ lines: [RFSLine]) {
        for line in lines {
            switch line.kind {
            case .screen: openScreen(line)
            case .app: applyApp(line)
            case .variable: declareVariable(line)
            case .edit: edit(line)
            case .delete: delete(line)
            case .nav: setNavigation(line)
            case .say: reply = ([reply].compactMap { $0 } + [line.positional.first ?? line.tokens.joined(separator: " ")]).joined(separator: "\n")
            case .component(let kw): addComponent(kw, line)
            case .end, .comment: break
            }
        }
        polish()
    }

    // MARK: Screens

    mutating func openScreen(_ line: RFSLine) {
        let name = (line.positional.first ?? line.attributes["name"] ?? line.tokens.first ?? "Screen").trimmingCharacters(in: .whitespaces)
        let flags = Set(line.flags)
        var index: Int
        if let existing = project.screen(named: name), let i = project.screenIndex(id: existing.id) {
            index = i
            if flags.contains("replace") || flags.contains("rebuild") {
                project.screens[i].root.children = []
                changes.append(ChangeRecord(.updatedScreen, "Rebuilt the \(existing.name) screen", screenID: existing.id))
            }
        } else {
            let icon = SymbolResolver.resolve(line.attributes["icon"] ?? "", fallback: SymbolResolver.symbol(forConcept: name, fallback: "square.grid.2x2"))
            var s = Screen(name: project.uniqueScreenName(name), title: line.attributes["title"] ?? name, icon: icon)
            s.largeTitle = !flags.contains("inline")
            if flags.contains("nobar") { s.showsNavigationBar = false }
            if let bg = line.attributes["bg"] ?? line.attributes["background"], let fill = fill(bg) { s.background = fill }
            project.screens.append(s)
            index = project.screens.count - 1
            if project.navigation.initialScreenID == nil { project.navigation.initialScreenID = s.id }
            changes.append(ChangeRecord(.addedScreen, "Created the \(s.name) screen", screenID: s.id))
        }
        let screenID = project.screens[index].id
        if flags.contains("tab") && !project.isTab(screenID) {
            project.setTab(screenID, enabled: true)
            changes.append(ChangeRecord(.navigation, "Added \(project.screens[index].name) to the tab bar", screenID: screenID))
        }
        if flags.contains("large") { project.screens[index].largeTitle = true }
        if flags.contains("home") || flags.contains("initial") || flags.contains("start") {
            project.navigation.initialScreenID = screenID
        }
        currentScreenIndex = index
        focusScreenID = screenID
        screenOpenedByScript = true
        stack = []
        insertAfterID = nil
    }

    mutating func ensureScreen() -> Int {
        if let i = currentScreenIndex, project.screens.indices.contains(i) { return i }
        if let first = project.screens.indices.first { currentScreenIndex = first; return first }
        let s = Screen(name: "Home", icon: "house.fill")
        project.addScreen(s)
        changes.append(ChangeRecord(.addedScreen, "Created the Home screen", screenID: s.id))
        currentScreenIndex = project.screens.count - 1
        screenOpenedByScript = true
        return currentScreenIndex!
    }

    /// Finds or creates a screen for navigation targets so links never dangle.
    mutating func screenForNavigation(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = project.screen(named: name) { return s.id }
        let title = name.isEmpty ? "Details" : name
        var s = Screen(name: project.uniqueScreenName(title), icon: SymbolResolver.symbol(forConcept: title, fallback: "doc.text"))
        s.root.children = [
            Node(type: .icon, props: ["symbol": .string(SymbolResolver.symbol(forConcept: title, fallback: "sparkles")), "size": 44]),
            Node(type: .text, props: ["text": .string("This is the \(title) screen. Ask ReyForge AI to design it, or drag components here.")], style: Style(foreground: "secondaryText")),
        ]
        project.screens.append(s)
        changes.append(ChangeRecord(.addedScreen, "Created the \(s.name) screen as a link target", screenID: s.id))
        return s.id
    }

    // MARK: Components

    mutating func addComponent(_ keyword: String, _ line: RFSLine) {
        guard var node = makeNode(keyword: keyword, line: line) else {
            warnings.append("Line \(line.lineNumber): unknown element “\(keyword)”")
            return
        }
        let si = ensureScreen()
        let rootID = project.screens[si].root.id
        while let top = stack.last, top.indent >= line.indent { stack.removeLast() }

        var parentID = stack.last?.id
        var insertAfter: String?
        if parentID == nil {
            if screenOpenedByScript {
                parentID = rootID
            } else if let sel = context.selectedNodeID, project.screenContaining(nodeID: sel)?.id == project.screens[si].id, let selNode = project.node(id: sel) {
                if ComponentRegistry.spec(for: selNode.type).isContainer && ComponentRegistry.canContain(selNode.type, node.type) {
                    parentID = sel
                } else {
                    insertAfter = insertAfterID ?? sel
                }
            } else {
                parentID = rootID
            }
        }
        // Menus only hold buttons; send anything else to the root.
        if let pid = parentID, let parent = project.node(id: pid), !(ComponentRegistry.canContain(parent.type, node.type) || pid == rootID) {
            parentID = rootID
        }
        // Free layout children need a position.
        if let pid = parentID, project.node(id: pid)?.type == .zstack, node.style.offsetX == nil {
            let count = project.node(id: pid)?.children.count ?? 0
            node.style.offsetX = 16 + Double(count % 3) * 24
            node.style.offsetY = 16 + Double(count) * 36
        }
        var inserted = false
        if let after = insertAfter {
            inserted = project.insert(node, after: after)
            if inserted { insertAfterID = node.id }
        }
        if !inserted {
            inserted = project.insert(node, into: parentID ?? rootID)
        }
        guard inserted else { warnings.append("Line \(line.lineNumber): could not place \(keyword)"); return }
        created.append(node.id)
        lastNodeID = node.id
        if ComponentRegistry.spec(for: node.type).isContainer {
            stack.append((line.indent, node.id))
            createdContainers.insert(node.id)
        }
        changes.append(ChangeRecord(.addedNode, "Added \(node.displayName)", screenID: project.screens[si].id, nodeID: node.id))
    }

    static let keywordTypes: [String: ComponentType] = [
        "TEXT": .text, "PARAGRAPH": .text, "BODY": .text, "P": .text, "TITLE": .text, "LARGETITLE": .text, "H1": .text, "HEADING": .text,
        "HEADLINE": .text, "H2": .text, "SUBHEADING": .text, "SUBTITLE": .text, "H3": .text, "CAPTION": .text, "NOTE": .text, "FOOTNOTE": .text, "SMALL": .text,
        "LABEL": .label, "IMAGE": .image, "PICTURE": .image, "IMG": .image, "BANNER": .image, "HERO": .image, "ICON": .icon, "SYMBOL": .icon,
        "AVATAR": .avatar, "BADGE": .badge, "TAG": .badge, "CHIP": .badge, "PILL": .badge, "DIVIDER": .divider, "SEPARATOR": .divider, "LINE": .divider,
        "SPACER": .spacer, "SPACE": .spacer, "GAP": .spacer, "SHAPE": .shape, "CIRCLE": .shape, "RECT": .shape, "RECTANGLE": .shape, "CAPSULE": .shape,
        "ELLIPSE": .shape, "GRADIENT": .gradient, "PROGRESS": .progress, "PROGRESSBAR": .progress, "SPINNER": .progress, "LOADER": .progress,
        "GAUGE": .gauge, "METER": .gauge, "RING": .gauge, "CHART": .chart, "GRAPH": .chart, "MAP": .map, "WEB": .web, "WEBVIEW": .web, "BROWSER": .web,
        "VIDEO": .video, "AUDIO": .audio, "PLAYER": .audio, "SONG": .audio, "STAT": .statCard, "KPI": .statCard, "METRIC": .statCard,
        "RATING": .rating, "STARS": .rating, "TIMER": .timer, "COUNTDOWN": .timer, "STOPWATCH": .timer, "EMPTY": .empty, "LINK": .link,
        "ROW": .listRow, "ITEM": .listRow, "CELL": .listRow, "BUTTON": .button, "BTN": .button, "CTA": .button, "TOGGLE": .toggle, "SWITCH": .toggle,
        "CHECKBOX": .toggle, "SLIDER": .slider, "STEPPER": .stepper, "PICKER": .picker, "SELECT": .picker, "DROPDOWN": .picker, "SEGMENTED": .picker,
        "TABS": .picker, "DATE": .datePicker, "DATEPICKER": .datePicker, "TIME": .datePicker, "CALENDAR": .datePicker, "COLOR": .colorPicker,
        "COLORPICKER": .colorPicker, "FIELD": .textField, "INPUT": .textField, "TEXTFIELD": .textField, "EMAIL": .textField, "SECURE": .secureField,
        "PASSWORD": .secureField, "EDITOR": .textEditor, "TEXTAREA": .textEditor, "SEARCH": .searchField, "SEARCHBAR": .searchField, "MENU": .menu,
        "SHARE": .shareLink, "PHOTO": .photoPicker, "PHOTOPICKER": .photoPicker, "UPLOAD": .photoPicker, "APPLE": .signInApple, "SIGNINAPPLE": .signInApple,
        "INFO": .labeledContent, "LABELED": .labeledContent, "DETAIL": .labeledContent, "QR": .qr, "QRCODE": .qr, "VSTACK": .vstack, "COLUMN": .vstack,
        "STACK": .vstack, "HSTACK": .hstack, "ZSTACK": .zstack, "FREE": .zstack, "CANVAS": .zstack, "SCROLL": .scroll, "CAROUSEL": .scroll, "GRID": .grid,
        "LIST": .list, "FORM": .form, "SECTION": .section, "CARD": .card, "BOX": .card, "PANEL": .card, "GROUP": .groupBox, "GROUPBOX": .groupBox,
        "DISCLOSURE": .disclosure, "ACCORDION": .disclosure, "EXPANDABLE": .disclosure, "PAGER": .pager, "PAGES": .pager, "SLIDES": .pager,
        "NAVLINK": .navLink, "NAVIGATIONLINK": .navLink,
    ]

    static func type(for keyword: String) -> ComponentType? {
        keywordTypes[keyword.uppercased()] ?? ComponentType.alias(keyword)
    }

    mutating func makeNode(keyword: String, line: RFSLine) -> Node? {
        let kw = keyword.uppercased()
        guard let type = RFSCompiler.type(for: kw) else { return nil }
        let spec = ComponentRegistry.spec(for: type)
        var node = Node(type: type, props: spec.defaultProps, style: spec.defaultStyle)
        // Keyword presets.
        switch kw {
        case "TITLE", "LARGETITLE", "H1":
            node.style.font = FontSpec(style: kw == "LARGETITLE" ? "largeTitle" : "title", weight: "bold")
        case "HEADING", "HEADLINE", "H2":
            node.style.font = FontSpec(style: "title3", weight: "semibold")
        case "SUBHEADING", "SUBTITLE", "H3":
            node.style.font = FontSpec(style: "headline")
        case "CAPTION", "NOTE", "FOOTNOTE", "SMALL":
            node.style.font = FontSpec(style: "subheadline")
            node.style.foreground = "secondaryText"
        case "CIRCLE": node.props["shape"] = "circle"; node.style.width = .fixed(80); node.style.height = .fixed(80)
        case "CAPSULE": node.props["shape"] = "capsule"
        case "ELLIPSE": node.props["shape"] = "ellipse"
        case "RECT", "RECTANGLE": node.props["shape"] = "rectangle"
        case "SEGMENTED", "TABS": node.props["variant"] = "segmented"
        case "SPINNER", "LOADER": node.props["value"] = .string(""); node.props["variant"] = "circular"; node.props["label"] = ""
        case "CHECKBOX": node.props["variant"] = "checkbox"
        case "TIME": node.props["components"] = "time"
        case "CALENDAR": node.props["variant"] = "graphical"
        case "EMAIL": node.props["keyboard"] = "email"; node.props["contentType"] = "email"; node.props["autocapitalize"] = "never"; node.props["icon"] = "envelope"
        case "STOPWATCH": node.props["mode"] = "stopwatch"
        case "BANNER", "HERO": node.style.height = .fixed(200)
        case "DROPDOWN", "SELECT": node.props["variant"] = "menu"
        case "STACK", "COLUMN": node.props["alignment"] = "leading"
        case "GROUP" where type == .groupBox: break
        default: break
        }
        applyPositional(line.positional, to: &node, line: line)
        apply(attributes: line.attributes, flags: line.flags, to: &node)
        if let actions = line.actions, !actions.isEmpty {
            let compiled = compileActions(actions)
            if !compiled.isEmpty {
                let event = eventKind(line.attributes["on"], for: node.type)
                node.events.append(EventHandler(event: event, actions: compiled))
            }
        }
        finalizeBinding(&node)
        return node
    }

    func eventKind(_ raw: String?, for type: ComponentType) -> EventKind {
        if let r = raw?.lowercased() {
            switch r {
            case "change", "changed": return .change
            case "submit", "return", "enter": return .submit
            case "appear", "load", "show": return .appear
            case "longpress", "hold", "long": return .longPress
            case "delete", "swipe": return .delete
            default: return .tap
            }
        }
        switch type {
        case .toggle, .slider, .stepper, .picker, .datePicker, .colorPicker, .rating, .photoPicker, .pager, .textEditor: return .change
        case .textField, .secureField, .searchField: return .submit
        default: return .tap
        }
    }

    // MARK: Positional arguments

    mutating func applyPositional(_ args: [String], to node: inout Node, line: RFSLine) {
        guard !args.isEmpty else { return }
        let a0 = args[0]
        let a1 = args.count > 1 ? args[1] : nil
        switch node.type {
        case .text: node.props["text"] = .string(args.joined(separator: " "))
        case .label:
            node.props["title"] = .string(a0)
            if let a1 = a1 { node.props["icon"] = .string(SymbolResolver.resolve(a1)) }
            else { node.props["icon"] = .string(SymbolResolver.symbol(forConcept: a0, fallback: "star.fill")) }
        case .image: node.props["source"] = .string(imageSource(a0))
        case .icon: node.props["symbol"] = .string(SymbolResolver.resolve(a0, fallback: SymbolResolver.symbol(forConcept: a0, fallback: "star.fill")))
        case .avatar:
            if a0.hasPrefix("http") { node.props["image"] = .string(a0) } else { node.props["name"] = .string(a0) }
        case .badge: node.props["text"] = .string(a0)
        case .shape: if let kind = shapeKind(a0) { node.props["shape"] = .string(kind) }
        case .gradient: node.props["colors"] = .array(a0.split(separator: ",").compactMap { color(String($0)) }.map { .string($0) })
        case .progress: node.props["label"] = .string(a0)
        case .gauge: node.props["label"] = .string(a0)
        case .chart:
            for a in args {
                if ["bar", "line", "area", "point", "pie", "donut"].contains(a.lowercased()) { node.props["kind"] = .string(a.lowercased()) }
                else if a.contains(":") || a.hasPrefix("[") { node.props["data"] = .string(a) }
                else if node.props["title"] == nil || node.props["title"] == ComponentRegistry.spec(for: .chart).defaultValue(for: "title") { node.props["title"] = .string(a) }
            }
        case .map:
            node.props["title"] = .string(a0)
            if let place = Places.lookup(a0) {
                node.props["latitude"] = .number(place.lat); node.props["longitude"] = .number(place.lon)
                node.props["markers"] = .string("\(place.name):\(place.lat),\(place.lon)")
            } else {
                node.props["geocode"] = .bool(true)
                node.props["markers"] = .string("")
            }
        case .web, .video: node.props["url"] = .string(a0)
        case .audio:
            if a0.hasPrefix("http") { node.props["url"] = .string(a0); if let a1 = a1 { node.props["title"] = .string(a1) } }
            else { node.props["title"] = .string(a0); if let a1 = a1 { node.props["artist"] = .string(a1) } }
        case .statCard:
            node.props["title"] = .string(a0)
            if let a1 = a1 { node.props["value"] = .string(a1) }
            if node.props["icon"] == ComponentRegistry.spec(for: .statCard).defaultValue(for: "icon") {
                node.props["icon"] = .string(SymbolResolver.symbol(forConcept: a0, fallback: "chart.bar.fill"))
            }
            if args.count > 2 { node.props["delta"] = .string(args[2]) } else { node.props["delta"] = "" }
        case .rating: if let n = Value.parseNumber(a0) { node.props["value"] = .number(n) }
        case .timer:
            if let n = Value.parseNumber(a0) { node.props["seconds"] = .number(n) } else if a0.lowercased().contains("stop") { node.props["mode"] = "stopwatch" }
        case .empty: node.props["title"] = .string(a0); if let a1 = a1 { node.props["message"] = .string(a1) }
        case .link: node.props["title"] = .string(a0); if let a1 = a1 { node.props["url"] = .string(a1) }
        case .listRow:
            node.props["title"] = .string(a0)
            if let a1 = a1 { node.props["subtitle"] = .string(a1) }
            if args.count > 2 { node.props["value"] = .string(args[2]) }
        case .button, .toggle, .slider, .stepper, .datePicker, .colorPicker, .photoPicker, .signInApple, .menu, .groupBox, .disclosure:
            node.props["title"] = .string(a0)
        case .picker:
            if node.props["variant"] == "segmented" && args.count == 1 && a0.contains(",") {
                node.props["title"] = .string("")
                node.props["options"] = list(a0)
            } else {
                node.props["title"] = .string(a0)
                if let a1 = a1 { node.props["options"] = list(a1) }
            }
        case .textField, .secureField, .textEditor, .searchField: node.props["placeholder"] = .string(a0)
        case .shareLink: node.props["title"] = .string(a0); if let a1 = a1 { node.props["item"] = .string(a1) }
        case .labeledContent: node.props["title"] = .string(a0); if let a1 = a1 { node.props["value"] = .string(a1) }
        case .qr: node.props["content"] = .string(a0)
        case .section: node.props["header"] = .string(a0); if let a1 = a1 { node.props["footer"] = .string(a1) }
        case .list: node.props["header"] = .string(a0)
        case .navLink:
            node.props["title"] = .string(a0)
            let dest = a1 ?? a0
            node.props["destination"] = .string(screenForNavigation(dest))
            if node.props["icon"] == ComponentRegistry.spec(for: .navLink).defaultValue(for: "icon") {
                node.props["icon"] = .string(SymbolResolver.symbol(forConcept: a0, fallback: "arrow.right.circle.fill"))
            }
        case .card, .vstack, .hstack, .zstack, .scroll, .grid, .form, .pager:
            // A title argument on a container becomes a heading inside it.
            if node.type == .card || node.type == .vstack {
                node.children.append(Node(type: .text, props: ["text": .string(a0)], style: Style(font: FontSpec(style: "headline"))))
            }
        case .spacer: if let n = Value.parseNumber(a0) { node.props["minLength"] = .number(n) }
        case .divider: break
        }
    }

    func imageSource(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("http") || t.hasPrefix("asset:") || t.hasPrefix("symbol:") { return t }
        if t.contains("."), !t.contains(" "), SymbolResolver.isKnown(t) { return "symbol:" + t }
        // A description: use a deterministic photo for the keyword.
        let seed = BundleID.slug(t).prefix(24)
        return "https://picsum.photos/seed/\(seed.isEmpty ? "reyforge" : String(seed))/800/500"
    }

    func shapeKind(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "circle", "round": return "circle"
        case "rect", "rectangle", "square": return "rectangle"
        case "rounded", "roundedrect", "roundedrectangle", "card": return "roundedRectangle"
        case "capsule", "pill": return "capsule"
        case "ellipse", "oval": return "ellipse"
        default: return nil
        }
    }

    func list(_ raw: String) -> Value {
        if raw.hasPrefix("["), let v = Value.fromJSONString(raw), case .array = v { return v }
        let sep: Character = raw.contains("|") ? "|" : ","
        return .array(raw.split(separator: sep).map { .string($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 != .string("") })
    }

    // MARK: Attributes

    func color(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        let lower = t.lowercased()
        let tokens = ["accent", "primary", "secondary", "background", "surface", "text", "secondarytext", "muted", "success", "warning", "danger", "tint", "clear", "card"]
        if tokens.contains(lower) {
            switch lower {
            case "primary", "tint": return "accent"
            case "muted": return "secondaryText"
            case "secondarytext": return "secondaryText"
            case "card": return "surface"
            default: return lower
            }
        }
        if ColorNames.isHex(t) { return ColorNames.normalizedHex(t) }
        if ColorNames.table[lower.replacingOccurrences(of: " ", with: "")] != nil { return lower.replacingOccurrences(of: " ", with: "") }
        return nil
    }

    func fill(_ raw: String) -> Fill? {
        let parts = raw.split(separator: ",").compactMap { color(String($0)) }
        if parts.isEmpty { return nil }
        return parts.count == 1 ? .solid(parts[0]) : .linear(parts)
    }

    func dimension(_ raw: String) -> Dimension? {
        let l = raw.lowercased()
        if ["fill", "full", "max", "infinity", "100%", "stretch"].contains(l) { return .fill }
        if let n = Value.parseNumber(raw), n > 0 { return .fixed(min(n, 2000)) }
        return nil
    }

    static let textStyleAliases: [String: String] = [
        "h1": "largeTitle", "large": "title2", "big": "title2", "huge": "largeTitle", "h2": "title", "h3": "title3", "small": "footnote",
        "tiny": "caption2", "normal": "body", "regular": "body", "subtitle": "subheadline", "caption1": "caption",
    ]

    static let variantAliases: [String: String] = [
        "primary": "prominent", "filled": "prominent", "solid": "prominent", "secondary": "bordered", "outline": "bordered", "outlined": "bordered",
        "tinted": "bordered", "danger": "destructive", "delete": "destructive", "text": "plain", "ghost": "borderless", "pill": "capsule",
        "rounded": "capsule", "liquid": "glass", "liquidglass": "glass",
    ]

    mutating func apply(attributes: [String: String], flags: [String], to node: inout Node) {
        let spec = ComponentRegistry.spec(for: node.type)
        let propKeys = Set(spec.properties.map { $0.key })
        func setProp(_ key: String, _ raw: String) {
            guard let ps = spec.properties.first(where: { $0.key == key }) else { return }
            switch ps.kind {
            case .number: if let n = Value.parseNumber(raw) { node.props[key] = .number(n) }
            case .bool: node.props[key] = .bool(Value.string(raw).boolValue)
            case .list: node.props[key] = list(raw)
            case .symbol: node.props[key] = .string(SymbolResolver.resolve(raw))
            case .image:
                let t = raw.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("http") || t.hasPrefix("asset:") || t.hasPrefix("symbol:") || t.isEmpty { node.props[key] = .string(t) }
                else { node.props[key] = .string(SymbolResolver.resolve(t)) }
            case .color: if let c = color(raw) { node.props[key] = .string(c) }
            case .options(let opts):
                let lower = raw.lowercased()
                if let match = opts.first(where: { $0.lowercased() == lower }) { node.props[key] = .string(match) }
                else if let alias = RFSCompiler.variantAliases[lower], opts.contains(alias) { node.props[key] = .string(alias) }
            case .screen: node.props[key] = .string(screenForNavigation(raw))
            case .expression:
                if let n = Value.parseNumber(raw), !raw.contains("{{") { node.props[key] = .number(n) } else { node.props[key] = .string(raw) }
            default: node.props[key] = .string(raw)
            }
        }
        func setColor(_ raw: String) {
            guard let c = color(raw) else { return }
            switch node.type {
            case .shape: node.props["fill"] = .string(c)
            case .badge, .chart, .rating: node.props["color"] = .string(c)
            case .statCard, .progress, .gauge, .toggle, .slider, .timer: node.props["tint"] = .string(c)
            case .button:
                node.props["tint"] = .string(c)
            case .listRow, .navLink, .label: node.props["iconColor"] = .string(c)
            case .gradient: node.props["colors"] = .array([.string(c), .string(ColorNames.mix(ColorNames.hex(for: c) ?? "#5B5BF7", "#000000", 0.35))])
            default: node.style.foreground = c
            }
        }

        for (rawKey, value) in attributes {
            let key = rawKey.lowercased()
            switch key {
            case "text", "content":
                if propKeys.contains("text") { setProp("text", value) } else { setProp(mainTextKey(node.type), value) }
            case "title", "label":
                if propKeys.contains("title") { setProp("title", value) }
                else if propKeys.contains("label") { setProp("label", value) }
                else { setProp(mainTextKey(node.type), value) }
            case "name":
                if propKeys.contains("name") { setProp("name", value) } else if propKeys.contains("title") { setProp("title", value) } else { node.name = value }
            case "layer": node.name = value
            case "subtitle", "detail", "description", "desc", "sub":
                if propKeys.contains("subtitle") { setProp("subtitle", value) } else if propKeys.contains("message") { setProp("message", value) } else if propKeys.contains("footer") { setProp("footer", value) }
            case "message", "body": if propKeys.contains("message") { setProp("message", value) } else if propKeys.contains("subtitle") { setProp("subtitle", value) }
            case "value", "amount", "initial", "default":
                if propKeys.contains("value") { setProp("value", value) }
                else if node.type == .toggle { node.props["isOn"] = .bool(Value.string(value).boolValue) }
            case "icon", "symbol", "sf", "systemimage":
                if propKeys.contains("icon") { setProp("icon", value) } else if propKeys.contains("symbol") { setProp("symbol", value) }
                else if node.type == .image { node.props["source"] = .string("symbol:" + SymbolResolver.resolve(value)) }
            case "image", "img", "photo", "src", "source" where node.type != .list && node.type != .grid && node.type != .scroll && node.type != .vstack && node.type != .hstack:
                if node.type == .image { node.props["source"] = .string(imageSource(value)) }
                else if propKeys.contains("image") { node.props["image"] = .string(value.hasPrefix("http") ? value : imageSource(value)) }
                else if propKeys.contains("artwork") { node.props["artwork"] = .string(imageSource(value)) }
                else if propKeys.contains("icon") { node.props["icon"] = .string(value.hasPrefix("http") ? value : SymbolResolver.resolve(value)) }
            case "source", "data", "items", "repeat", "foreach", "from":
                if node.type == .chart, key == "data" || key == "source" {
                    if value.contains(":") || value.hasPrefix("[") { node.props["data"] = .string(value) } else { node.props["data"] = .string("{{\(Variable.sanitize(value))}}") }
                } else if node.type == .picker, key == "items" {
                    node.props["options"] = list(value)
                } else if spec.supportsRepeat || spec.isContainer {
                    let v = value.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "")
                    let name = Variable.sanitize(v)
                    node.repeatSource = name
                    project.ensureVariable(name, type: .list, initial: .array([]))
                } else if propKeys.contains("data") { setProp("data", value) }
            case "visible", "if", "show", "when", "visibleif": node.visibleIf = value
            case "bind", "binding", "var", "variable", "model", "state":
                node.binding = Variable.sanitize(value)
            case "url", "href", "link", "website":
                if propKeys.contains("url") { setProp("url", value) } else if propKeys.contains("item") { setProp("item", value) }
                else if node.type == .image { node.props["source"] = .string(value) }
            case "placeholder", "hint", "prompt": if propKeys.contains("placeholder") { setProp("placeholder", value) }
            case "options", "choices", "values": if propKeys.contains("options") { setProp("options", value) }
            case "min", "minimum", "from_": setProp("min", value)
            case "max", "maximum", "total", "of":
                if propKeys.contains("max") { setProp("max", value) } else if propKeys.contains("total") { setProp("total", value) }
            case "step": setProp("step", value)
            case "color", "tint", "fg", "foreground", "textcolor", "iconcolor": setColor(value)
            case "bg", "background", "backgroundcolor":
                if let f = fill(value) { node.style.background = f }
            case "fill":
                if node.type == .shape, let c = color(value) { node.props["fill"] = .string(c) } else if let f = fill(value) { node.style.background = f }
            case "stroke", "border", "bordercolor":
                if node.type == .shape { if let c = color(value) { node.props["strokeColor"] = .string(c); if node.props["strokeWidth"] == .number(0) { node.props["strokeWidth"] = 2 } } }
                else if let c = color(value) { node.style.borderColor = c; node.style.borderWidth = node.style.borderWidth ?? 1 }
            case "borderwidth", "strokewidth":
                if let n = Value.parseNumber(value) { if node.type == .shape { node.props["strokeWidth"] = .number(n) } else { node.style.borderWidth = n } }
            case "width", "w": if let d = dimension(value) { node.style.width = d }
            case "height", "h": if let d = dimension(value) { node.style.height = d }
            case "minheight": node.style.minHeight = Value.parseNumber(value)
            case "padding", "pad", "inset": if let n = Value.parseNumber(value) { node.style.padding = Insets(all: n) }
            case "margin": if let n = Value.parseNumber(value) { node.style.margin = Insets(all: n) }
            case "radius", "corner", "corners", "cornerradius", "rounded", "round":
                if let n = Value.parseNumber(value) { node.style.cornerRadius = n }
            case "opacity", "alpha": if let n = Value.parseNumber(value) { node.style.opacity = n > 1 ? n / 100 : n }
            case "rotation", "rotate", "angle":
                if node.type == .gradient { setProp("angle", value) } else { node.style.rotation = Value.parseNumber(value) }
            case "shadow", "elevation":
                switch value.lowercased() {
                case "none", "false", "0": node.style.shadow = nil
                case "large", "lg", "big": node.style.shadow = .large
                case "small", "sm": node.style.shadow = .small
                default: node.style.shadow = .medium
                }
            case "x", "left": node.style.offsetX = Value.parseNumber(value)
            case "y", "top": node.style.offsetY = Value.parseNumber(value)
            case "z", "zindex": node.style.zIndex = Value.parseNumber(value)
            case "align", "alignment", "textalign":
                let a = value.lowercased()
                let mapped = a == "left" ? "leading" : (a == "right" ? "trailing" : (a == "middle" ? "center" : a))
                if propKeys.contains("alignment") { setProp("alignment", mapped) }
                if let h = HAlign(rawValue: mapped) { node.style.alignment = h }
            case "spacing", "gap": setProp("spacing", value)
            case "columns", "cols": setProp("columns", value)
            case "header": setProp("header", value)
            case "footer": setProp("footer", value)
            case "keyboard", "keyboardtype", "input": setProp("keyboard", value)
            case "mode", "components":
                if node.type == .datePicker {
                    let m = value.lowercased()
                    node.props["components"] = .string(m.contains("both") || m.contains("datetime") ? "dateTime" : (m.contains("time") ? "time" : "date"))
                } else if propKeys.contains("mode") { setProp("mode", value) }
            case "kind", "type", "chart":
                if propKeys.contains("kind") { setProp("kind", value) } else if propKeys.contains("shape"), let k = shapeKind(value) { node.props["shape"] = .string(k) }
            case "shape": if let k = shapeKind(value) { node.props["shape"] = .string(k) }
            case "delta", "change", "trend", "diff": setProp("delta", value)
            case "lat", "latitude": setProp("latitude", value); node.props["geocode"] = .bool(false)
            case "lon", "lng", "long", "longitude": setProp("longitude", value); node.props["geocode"] = .bool(false)
            case "zoom", "span":
                if let n = Value.parseNumber(value) { node.props["span"] = .number(n > 1 && key == "zoom" ? max(0.002, 0.5 / n) : n) }
            case "markers", "pins": setProp("markers", value)
            case "seconds", "duration": setProp("seconds", value)
            case "accessory": setProp("accessory", value)
            case "badge": setProp("badge", value)
            case "item", "share": setProp("item", value)
            case "destination", "dest", "screen", "target", "to": if propKeys.contains("destination") { setProp("destination", value) }
            case "lines", "linelimit", "maxlines": setProp("lineLimit", value)
            case "glass": node.style.glass = Value.string(value).boolValue
            case "font", "design", "fontdesign":
                var f = node.style.font ?? FontSpec()
                let l = value.lowercased()
                if FontSpec.designs.contains(l) { f.design = l } else if l == "mono" { f.design = "monospaced" }
                else if let n = Value.parseNumber(value) { f.size = n }
                else if FontSpec.textStyles.contains(value) { f.style = value }
                node.style.font = f
            case "weight", "fontweight":
                var f = node.style.font ?? FontSpec()
                let l = value.lowercased()
                f.weight = FontSpec.weights.first { $0.lowercased() == l } ?? (l == "normal" ? "regular" : f.weight)
                node.style.font = f
            case "fontsize", "textsize":
                var f = node.style.font ?? FontSpec(); f.size = Value.parseNumber(value); node.style.font = f
            case "style", "variant", "appearance":
                applyStyleWord(value, to: &node)
            case "size":
                applySize(value, to: &node)
            case "on", "event": break
            default:
                if propKeys.contains(key) { setProp(key, value) }
                else if let match = spec.properties.first(where: { $0.key.lowercased() == key }) { setProp(match.key, value) }
                else { warnings.append("Ignored attribute \(rawKey) on \(spec.title)") }
            }
        }

        for flag in flags {
            switch flag {
            case "bold": var f = node.style.font ?? FontSpec(); f.weight = "bold"; node.style.font = f
            case "semibold": var f = node.style.font ?? FontSpec(); f.weight = "semibold"; node.style.font = f
            case "italic": var f = node.style.font ?? FontSpec(); f.italic = true; node.style.font = f
            case "rounded", "serif", "monospaced", "mono":
                var f = node.style.font ?? FontSpec(); f.design = flag == "mono" ? "monospaced" : flag; node.style.font = f
            case "center", "centered": if propKeys.contains("alignment") { node.props["alignment"] = "center" }; node.style.alignment = .center
            case "leading", "left": if propKeys.contains("alignment") { node.props["alignment"] = "leading" }
            case "trailing", "right": if propKeys.contains("alignment") { node.props["alignment"] = "trailing" }
            case "full", "fullwidth", "wide", "block":
                if propKeys.contains("fullWidth") { node.props["fullWidth"] = true } else { node.style.width = .fill }
            case "compact", "inline":
                if propKeys.contains("fullWidth") { node.props["fullWidth"] = false }
                if node.type == .datePicker { node.props["variant"] = "compact" }
            case "destructive", "danger":
                if node.type == .button { node.props["variant"] = "destructive"; node.props["role"] = "destructive" }
            case "chevron", "disclosure", "arrow": if propKeys.contains("accessory") { node.props["accessory"] = "chevron" }
            case "checkmark", "checked": if propKeys.contains("accessory") { node.props["accessory"] = "checkmark" }
            case "horizontal": if node.type == .scroll { node.props["axis"] = "horizontal" }
            case "vertical": if node.type == .scroll { node.props["axis"] = "vertical" }
            case "paging", "paged": if node.type == .scroll { node.props["paging"] = true }
            case "circular", "ring", "radial":
                if node.type == .progress { node.props["variant"] = "circular" }
                if node.type == .gauge { node.props["variant"] = "circularCapacity" }
                if node.type == .gradient { node.props["kind"] = "radial" }
            case "linear": if node.type == .gauge { node.props["variant"] = "linearCapacity" }; if node.type == .progress { node.props["variant"] = "linear" }
            case "bar", "line", "area", "point", "pie", "donut": if node.type == .chart { node.props["kind"] = .string(flag) }
            case "circle", "rectangle", "rect", "capsule", "ellipse", "oval", "square":
                if node.type == .shape, let k = shapeKind(flag) { node.props["shape"] = .string(k) }
                if node.type == .image, flag == "circle" { node.style.clip = .circle }
            case "graphical", "wheel":
                if node.type == .datePicker { node.props["variant"] = .string(flag) }
                if node.type == .picker && flag == "wheel" { node.props["variant"] = "wheel" }
            case "segmented", "menu", "palette": if node.type == .picker { node.props["variant"] = .string(flag) }
            case "on", "checkedon", "enabled": if node.type == .toggle { node.props["isOn"] = true }
            case "off", "disabled": if node.type == .toggle { node.props["isOn"] = false }
            case "shadow": node.style.shadow = .medium
            case "glass": node.style.glass = true
            case "fit", "fill":
                if node.type == .image { node.props["contentMode"] = .string(flag) }
            case "autoplay": if node.type == .video { node.props["autoplay"] = true }
            case "loop": if node.type == .video { node.props["loops"] = true }
            case "hidden": node.visibleIf = "false"
            case "stopwatch": if node.type == .timer { node.props["mode"] = "stopwatch" }
            case "secure": break
            case "prominent", "bordered", "plain", "borderless", "capsule_", "link": applyStyleWord(flag, to: &node)
            case "small", "large", "big", "regular", "bigger", "smaller", "larger", "huge", "tiny": applySize(flag, to: &node)
            default: break
            }
        }
    }

    func mainTextKey(_ type: ComponentType) -> String {
        switch type {
        case .text, .badge: return "text"
        case .textField, .secureField, .textEditor, .searchField: return "placeholder"
        case .gauge, .progress: return "label"
        case .qr: return "content"
        case .section, .list: return "header"
        case .avatar: return "name"
        case .image: return "overlayText"
        case .icon: return "symbol"
        default: return "title"
        }
    }

    func applyStyleWord(_ raw: String, to node: inout Node) {
        let l = raw.lowercased()
        let spec = ComponentRegistry.spec(for: node.type)
        if node.type == .text || node.type == .label || node.type == .link {
            if let s = FontSpec.textStyles.first(where: { $0.lowercased() == l }) ?? RFSCompiler.textStyleAliases[l] {
                var f = node.style.font ?? FontSpec(); f.style = s
                if s == "largeTitle" || s == "title" { f.weight = f.weight ?? "bold" }
                node.style.font = f
                return
            }
        }
        if let variant = spec.properties.first(where: { $0.key == "variant" }), case .options(let opts) = variant.kind {
            if let match = opts.first(where: { $0.lowercased() == l }) { node.props["variant"] = .string(match); if match == "destructive" { node.props["role"] = "destructive" }; return }
            if let alias = RFSCompiler.variantAliases[l], opts.contains(alias) { node.props["variant"] = .string(alias); if alias == "destructive" { node.props["role"] = "destructive" }; return }
        }
        if node.type == .progress && (l == "circular" || l == "ring") { node.props["variant"] = "circular" }
        if node.type == .gauge {
            if l.contains("circ") || l.contains("ring") { node.props["variant"] = "circularCapacity" }
            if l.contains("lin") || l.contains("bar") { node.props["variant"] = "linearCapacity" }
        }
        if node.type == .chart, ["bar", "line", "area", "point", "pie", "donut"].contains(l) { node.props["kind"] = .string(l) }
    }

    func applySize(_ raw: String, to node: inout Node) {
        let l = raw.lowercased()
        let bigger = ["large", "big", "bigger", "larger", "huge", "xl", "lg"].contains(l)
        let smaller = ["small", "smaller", "tiny", "sm", "xs", "mini"].contains(l)
        let number = Value.parseNumber(raw)
        switch node.type {
        case .button:
            if bigger { node.props["size"] = "large"; if l == "bigger" || l == "larger" || l == "huge" { var f = node.style.font ?? FontSpec(); f.style = "title3"; f.weight = "semibold"; node.style.font = f } }
            else if smaller { node.props["size"] = "small" }
            else if l == "regular" || l == "medium" { node.props["size"] = "regular" }
            else if let n = number { var f = node.style.font ?? FontSpec(); f.size = n; node.style.font = f }
        case .icon:
            if let n = number { node.props["size"] = .number(n) }
            else { let cur = node.number("size") ?? 32; node.props["size"] = .number(bigger ? cur * 1.5 : (smaller ? max(12, cur / 1.5) : cur)) }
        case .avatar, .qr:
            if let n = number { node.props["size"] = .number(n) }
            else { let cur = node.number("size") ?? 56; node.props["size"] = .number(bigger ? cur * 1.4 : (smaller ? cur / 1.4 : cur)) }
        case .image, .map, .chart, .web, .video, .gradient, .zstack, .pager:
            if let n = number { node.style.height = .fixed(n) }
            else if case .fixed(let h)? = node.style.height { node.style.height = .fixed(bigger ? h * 1.4 : (smaller ? h / 1.4 : h)) }
        default:
            var f = node.style.font ?? FontSpec()
            if let n = number { f.size = n }
            else {
                let order = ["caption2", "caption", "footnote", "subheadline", "callout", "body", "headline", "title3", "title2", "title", "largeTitle"]
                let current = f.style ?? "body"
                let idx = order.firstIndex(of: current) ?? 5
                if bigger { f.style = order[min(order.count - 1, idx + 2)] }
                if smaller { f.style = order[max(0, idx - 2)] }
            }
            node.style.font = f
        }
    }

    mutating func finalizeBinding(_ node: inout Node) {
        let spec = ComponentRegistry.spec(for: node.type)
        guard let kind = spec.bindable else { return }
        if let raw = node.binding, !raw.isEmpty {
            var initial: Value?
            switch node.type {
            case .toggle: initial = node.prop("isOn")
            case .slider, .stepper: initial = node.prop("value")
            case .rating: initial = node.prop("value").numberValue.map { .number($0) }
            case .picker: initial = node.prop("options").arrayValue.first
            case .disclosure: initial = node.prop("expanded")
            default: initial = nil
            }
            node.binding = project.ensureVariable(raw, type: kind, initial: initial)
        } else if [.toggle, .slider, .stepper, .picker, .textField, .secureField, .textEditor, .searchField, .datePicker, .colorPicker].contains(node.type) {
            // Auto-bind inputs so the logic editor can use them immediately.
            let base = node.string("title").isEmpty ? node.string("placeholder") : node.string("title")
            let name = Variable.sanitize(base.isEmpty ? node.type.rawValue : base)
            var initial: Value?
            switch node.type {
            case .toggle: initial = node.prop("isOn")
            case .slider, .stepper: initial = node.prop("value")
            case .picker: initial = node.prop("options").arrayValue.first
            default: initial = nil
            }
            let existing = project.variable(named: name)
            if existing == nil || existing?.type == kind {
                node.binding = project.ensureVariable(name, type: kind, initial: initial)
            }
        }
    }

    // MARK: Actions

    public mutating func compileActions(_ source: String) -> [Action] {
        var out: [Action] = []
        for part in RFSParser.splitActions(source) {
            if let a = compileAction(part) { out.append(a) }
        }
        if !out.isEmpty {
            changes.append(ChangeRecord(.logic, "Wired actions: " + out.map { ActionRegistry.describe($0, screenName: { self.project.screenName($0) }) }.joined(separator: ", ")))
        }
        return out
    }

    mutating func compileAction(_ raw: String) -> Action? {
        guard let p = RFSParser.parseAction(raw) else { return nil }
        let args = p.args.map { RFSParser.unquote($0) }
        let joined = args.joined(separator: " ")
        func first() -> String { args.first ?? "" }
        func isURL(_ s: String) -> Bool { s.contains("://") || s.hasPrefix("www.") || s.hasPrefix("tel:") || s.hasPrefix("mailto:") || s.hasPrefix("sms:") || s.hasPrefix("maps:") }
        switch p.verb {
        case "go", "goto", "push", "navigate", "show", "nav":
            if isURL(first()) { return .open(first()) }
            return .navigate(screenForNavigation(first().isEmpty ? "Details" : stripTo(first(), args)), style: "push")
        case "open":
            if isURL(first()) { return .open(first()) }
            return .navigate(screenForNavigation(stripTo(first(), args)), style: "push")
        case "sheet", "present", "modal", "popup":
            return .navigate(screenForNavigation(stripTo(first(), args)), style: "sheet")
        case "cover", "fullscreen", "full":
            return .navigate(screenForNavigation(stripTo(first(), args)), style: "fullScreen")
        case "root", "replace", "reset_to", "home":
            if p.verb == "home" && args.isEmpty, let initial = project.initialScreen { return .navigate(initial.id, style: "replace") }
            return .navigate(screenForNavigation(stripTo(first(), args)), style: "replace")
        case "tab", "switch", "switchtab": return .switchTab(screenForNavigation(stripTo(first(), args)))
        case "back", "dismiss", "close", "pop", "return": return .back()
        case "alert", "popup_alert":
            var a = Action.alert(args.first ?? "Done", args.count > 1 ? args[1] : "")
            if let b = p.block { a.then = compileActionList(b) }
            return a
        case "confirm", "ask":
            var a = Action.confirm(args.first ?? "Are you sure?", args.count > 1 ? args[1] : "", confirmLabel: args.count > 2 ? args[2] : "Confirm",
                                   destructive: args.contains { $0.lowercased() == "destructive" }, then: [])
            if let b = p.block { a.then = compileActionList(b) }
            if let e = p.elseBlock { a.otherwise = compileActionList(e) }
            return a
        case "toast", "notify_toast", "message", "say", "banner", "snackbar":
            let style = args.count > 1 && ["success", "info", "warning", "error"].contains(args[1].lowercased()) ? args[1].lowercased() : "success"
            return .toast(args.first ?? "Done", style: style)
        case "set", "assign", "let", "update":
            // set name = value | set name to value | set name value
            var rest = args
            guard !rest.isEmpty else { return nil }
            var name = rest.removeFirst()
            var valueText: String
            if let eq = name.firstIndex(of: "=") {
                valueText = String(name[name.index(after: eq)...]) + (rest.isEmpty ? "" : " " + rest.joined(separator: " "))
                name = String(name[..<eq])
            } else {
                if let f = rest.first, f == "=" || f.lowercased() == "to" { rest.removeFirst() }
                valueText = rest.joined(separator: " ")
            }
            valueText = valueText.trimmingCharacters(in: .whitespaces)
            let parsed = Value.parseLiteral(valueText)
            let kind: ValueKind
            switch parsed {
            case .bool: kind = .bool
            case .number: kind = .number
            case .array: kind = .list
            case .object: kind = .object
            default:
                kind = valueText.contains(where: { "+-*/".contains($0) }) && !valueText.contains("\"") ? .number : .text
            }
            let v = project.ensureVariable(name, type: project.variable(named: Variable.sanitize(name))?.type ?? kind, initial: nil)
            noteVariable(v)
            return .set(v, valueText)
        case "toggle", "flip":
            let v = project.ensureVariable(first(), type: .bool, initial: .bool(false)); noteVariable(v)
            return .toggle(v)
        case "inc", "increment", "add1", "plus", "++":
            let v = project.ensureVariable(first(), type: .number, initial: .number(0)); noteVariable(v)
            return .increment(v, by: args.count > 1 ? (Value.parseNumber(args[1]) ?? 1) : 1)
        case "dec", "decrement", "minus", "--":
            let v = project.ensureVariable(first(), type: .number, initial: .number(0)); noteVariable(v)
            var a = Action.decrement(v, by: args.count > 1 ? (Value.parseNumber(args[1]) ?? 1) : 1)
            a.params["min"] = 0
            return a
        case "add", "append", "push_item", "insert":
            guard !args.isEmpty else { return nil }
            let v = project.ensureVariable(args[0], type: .list, initial: .array([])); noteVariable(v)
            var item = args.dropFirst().joined(separator: " ")
            if item.isEmpty { item = "New item" }
            // A bare identifier refers to a variable's current value.
            if item.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), project.variable(named: item) != nil { item = "{{\(item)}}" }
            return .append(v, item: item)
        case "remove", "delete", "pop_item":
            guard !args.isEmpty else { return nil }
            let v = project.ensureVariable(args[0], type: .list, initial: .array([])); noteVariable(v)
            return .remove(v, index: args.count > 1 ? args[1] : "{{index}}")
        case "clear", "empty":
            let v = project.ensureVariable(first(), type: .list, initial: .array([])); noteVariable(v)
            return .clear(v)
        case "reset":
            return Action(kind: .resetVariables, params: ["variables": .string(args.joined(separator: ","))])
        case "if", "when":
            var condition = joined
            if condition.lowercased().hasSuffix(" then") { condition = String(condition.dropLast(5)) }
            return .when(condition, then: compileActionList(p.block ?? ""), else: compileActionList(p.elseBlock ?? ""))
        case "validate", "require", "check":
            let message = args.count > 1 ? args.last! : "Please check your input."
            let condition = args.count > 1 ? args.dropLast().joined(separator: " ") : joined
            return .validate(condition, message: message, then: compileActionList(p.block ?? ""))
        case "url", "link", "web", "browse", "safari": return .open(first())
        case "call", "phone": return .open(first().hasPrefix("tel:") ? first() : "tel:" + first().filter { $0.isNumber || $0 == "+" })
        case "email", "mail": return .open(first().hasPrefix("mailto:") ? first() : "mailto:" + first())
        case "share": return .share(joined.isEmpty ? "Check out this app!" : joined)
        case "copy", "clipboard": return .copy(joined)
        case "haptic", "vibrate", "feedback": return .haptic(args.first?.lowercased() ?? "success")
        case "wait", "delay", "sleep": return .delay(Value.parseNumber(first()) ?? 1)
        case "get", "fetch", "load", "request", "api", "post", "put", "patch":
            let url = args.first(where: { $0.hasPrefix("http") }) ?? first()
            var into = ""
            var path = ""
            if let i = args.firstIndex(where: { $0.lowercased() == "into" || $0.lowercased() == "to" || $0.lowercased() == "as" }), i + 1 < args.count {
                into = args[i + 1]
                if i + 2 < args.count { path = args[i + 2] }
            }
            if into.isEmpty { into = "response" }
            let v = project.ensureVariable(into, type: path.isEmpty ? .object : .text); noteVariable(v)
            let method = ["post", "put", "patch"].contains(p.verb) ? p.verb.uppercased() : "GET"
            var body = ""
            if let b = args.first(where: { $0.hasPrefix("body=") }) { body = String(b.dropFirst(5)) }
            return .api(url, method: method, into: v, path: path, body: body, then: compileActionList(p.block ?? ""), otherwise: compileActionList(p.elseBlock ?? ""))
        case "notify", "notification", "remind", "reminder":
            var seconds: Double = 5
            if let i = args.firstIndex(where: { $0.lowercased() == "in" }), i + 1 < args.count { seconds = Value.parseNumber(args[i + 1]) ?? 5 }
            let texts = args.filter { $0.lowercased() != "in" && Value.parseNumber($0) == nil }
            return .notify(texts.first ?? "Reminder", texts.count > 1 ? texts[1] : "", after: seconds)
        default:
            warnings.append("Unknown action “\(p.verb)”")
            return nil
        }
    }

    /// "go to Settings" → "Settings".
    func stripTo(_ first: String, _ args: [String]) -> String {
        var a = args
        if let f = a.first?.lowercased(), f == "to" || f == "the" { a.removeFirst() }
        if let f = a.first?.lowercased(), f == "the" { a.removeFirst() }
        if let l = a.last?.lowercased(), l == "screen" || l == "page" { a.removeLast() }
        return a.isEmpty ? first : a.joined(separator: " ")
    }

    mutating func compileActionList(_ s: String) -> [Action] {
        RFSParser.splitActions(s).compactMap { compileAction($0) }
    }

    mutating func noteVariable(_ name: String) {
        if !changes.contains(where: { $0.kind == .variable && $0.summary.hasSuffix("“\(name)”") }) {
            changes.append(ChangeRecord(.variable, "Uses variable “\(name)”"))
        }
    }

    // MARK: Statements

    mutating func declareVariable(_ line: RFSLine) {
        let toks = line.tokens
        guard let rawName = toks.first else { return }
        let typeWord = toks.count > 1 ? toks[1].lowercased() : "text"
        let kind: ValueKind
        switch typeWord {
        case "number", "int", "integer", "double", "float", "num": kind = .number
        case "bool", "boolean", "flag", "toggle": kind = .bool
        case "list", "array", "items": kind = .list
        case "date", "time", "datetime": kind = .date
        case "color", "colour": kind = .color
        case "object", "json", "dict", "map": kind = .object
        case "image", "photo": kind = .image
        default: kind = .text
        }
        let rest = toks.count > 2 ? toks[2...].joined(separator: " ") : ""
        let initial: Value? = rest.isEmpty ? nil : kind.coerce(Value.parseLiteral(rest))
        let name = Variable.sanitize(rawName)
        if let i = project.variables.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            project.variables[i].type = kind
            if let initial = initial { project.variables[i].initial = initial }
            changes.append(ChangeRecord(.variable, "Updated variable “\(project.variables[i].name)”"))
        } else {
            var v = Variable(name: name, type: kind, initial: initial)
            if line.flags.contains("persist") || line.flags.contains("saved") || line.attributes["persist"] != nil { v.persist = true }
            if let f = line.attributes["formula"] { v.formula = f }
            project.variables.append(v)
            changes.append(ChangeRecord(.variable, "Created variable “\(name)” (\(kind.title))"))
        }
    }

    mutating func applyApp(_ line: RFSLine) {
        var t = project.theme
        var b = project.brand
        var touchedTheme = false
        var touchedBrand = false
        for (k, v) in line.attributes {
            switch k {
            case "name", "appname", "displayname", "title":
                b.displayName = v; project.name = v; touchedBrand = true
            case "tagline", "slogan": b.tagline = v; touchedBrand = true
            case "accent", "primary", "color", "tint", "brand":
                if let c = color(v) { t.accent = ColorNames.hex(for: c) ?? c; touchedTheme = true }
            case "secondary", "accent2": if let c = color(v) { t.secondaryAccent = ColorNames.hex(for: c) ?? c; touchedTheme = true }
            case "bg", "background":
                if let c = color(v) { let hex = ColorNames.hex(for: c) ?? c; t.background = hex; if ColorNames.luminance(hex) < 0.2 { t.darkBackground = hex }; touchedTheme = true }
            case "surface", "card": if let c = color(v) { t.surface = ColorNames.hex(for: c) ?? c; touchedTheme = true }
            case "text", "foreground": if let c = color(v) { t.text = ColorNames.hex(for: c) ?? c; touchedTheme = true }
            case "theme", "appearance", "mode":
                let l = v.lowercased()
                t.appearance = l.contains("dark") ? .dark : (l.contains("light") ? .light : .system); touchedTheme = true
            case "font", "design", "typography":
                let l = v.lowercased()
                t.fontDesign = FontSpec.designs.contains(l) ? l : (l == "mono" ? "monospaced" : (l.contains("serif") ? "serif" : (l.contains("round") ? "rounded" : "default")))
                touchedTheme = true
            case "radius", "corner", "corners": if let n = Value.parseNumber(v) { t.cornerRadius = n; touchedTheme = true }
            case "preset", "style", "palette":
                if let p = ThemePresets.named(v) {
                    let appearance = t.appearance
                    t = p.theme
                    if appearance != .system && p.theme.appearance == .system { t.appearance = appearance }
                    b.icon.background = .linear(p.iconBackground)
                    touchedTheme = true; touchedBrand = true
                }
            case "icon":
                b.icon.kind = .symbol; b.icon.symbol = SymbolResolver.resolve(v, fallback: "sparkles"); touchedBrand = true
            case "iconbg", "iconbackground": if let f = fill(v) { b.icon.background = f; touchedBrand = true }
            case "iconcolor", "glyph": if let c = color(v) { b.icon.glyphColor = ColorNames.hex(for: c) ?? c; touchedBrand = true }
            case "emoji": b.icon.kind = .emoji; b.icon.emoji = v; touchedBrand = true
            case "splash":
                let l = v.lowercased()
                if ["none", "off", "false"].contains(l) { b.splash.enabled = false } else { b.splash.enabled = true; b.splash.animation = SplashSpec.Animation(rawValue: l) ?? .zoom }
                touchedBrand = true
            case "bundle", "bundleid": if BundleID.isValid(v) { project.bundleID = v }
            case "version": project.version = v
            default: break
            }
        }
        for f in line.flags {
            switch f {
            case "dark": t.appearance = .dark; touchedTheme = true
            case "light": t.appearance = .light; touchedTheme = true
            case "system", "auto": t.appearance = .system; touchedTheme = true
            case "rounded", "serif", "monospaced": t.fontDesign = f; touchedTheme = true
            default:
                if let p = ThemePresets.named(f) { t = p.theme; b.icon.background = .linear(p.iconBackground); touchedTheme = true; touchedBrand = true }
            }
        }
        if touchedTheme {
            // Keep the icon in sync with the accent unless the user designed it separately.
            if !touchedBrand { b.icon.background = .linear([t.accent, t.secondaryAccent]) }
            project.theme = t
            changes.append(ChangeRecord(.theme, describeTheme(t)))
        }
        if touchedBrand {
            project.brand = b
            changes.append(ChangeRecord(.brand, "Updated branding for \(b.displayName)"))
        }
    }

    func describeTheme(_ t: Theme) -> String {
        var parts: [String] = []
        parts.append("accent \(t.accent)")
        if t.appearance != .system { parts.append("\(t.appearance.rawValue) appearance") }
        if t.fontDesign != "default" { parts.append("\(t.fontDesign) font") }
        return "Updated the theme: " + parts.joined(separator: ", ")
    }

    mutating func setNavigation(_ line: RFSLine) {
        let word = (line.tokens.first ?? "").lowercased()
        if word.contains("tab") {
            if project.navigation.tabs.isEmpty {
                for s in project.screens.prefix(4) { project.setTab(s.id, enabled: true) }
            }
            project.navigation.style = project.navigation.tabs.isEmpty ? .stack : .tabs
            changes.append(ChangeRecord(.navigation, "Switched to tab bar navigation"))
        } else {
            project.navigation.style = .stack
            changes.append(ChangeRecord(.navigation, "Switched to stack navigation"))
        }
    }

    // MARK: Edit & delete

    func resolveTarget(_ line: RFSLine) -> [String] {
        let toks = line.tokens
        let first = toks.first?.lowercased() ?? "selected"
        switch first {
        case "selected", "this", "it", "selection", "current":
            if let s = context.selectedNodeID { return [s] }
            return context.lastTouchedNodeIDs.suffix(1)
        case "last", "previous":
            if let l = lastNodeID { return [l] }
            return context.lastTouchedNodeIDs.suffix(1)
        case "all":
            // EDIT all buttons color=red
            let typeWord = toks.count > 1 ? toks[1] : ""
            let singular = typeWord.hasSuffix("s") ? String(typeWord.dropLast()) : typeWord
            guard let type = RFSCompiler.type(for: singular) else { return [] }
            let sid = currentScreenIndex.map { project.screens[$0].id }
            return project.allNodes.filter { $0.node.type == type && (sid == nil || $0.screen.id == sid) }.map { $0.node.id }
        default: break
        }
        if first.hasPrefix("#") {
            let id = String(first.dropFirst())
            if project.node(id: id) != nil { return [id] }
            if let n = project.allNodes.first(where: { $0.node.id.hasPrefix(id) || $0.node.id.hasSuffix(id) }) { return [n.node.id] }
        }
        // EDIT BUTTON "Continue" … or EDIT "Continue" …
        var typeFilter: ComponentType?
        var needle = toks.first ?? ""
        if let t = RFSCompiler.type(for: needle.uppercased()), toks.count > 1, !needle.contains(" ") {
            typeFilter = t
            needle = toks[1]
        }
        let q = needle.lowercased()
        let candidates = project.allNodes.filter { pair in
            if let tf = typeFilter, pair.node.type != tf { return false }
            for key in ["text", "title", "label", "placeholder", "header", "name"] {
                if pair.node.props[key]?.stringValue.lowercased().contains(q) == true { return true }
            }
            return pair.node.name?.lowercased().contains(q) == true
        }
        let sid = currentScreenIndex.map { project.screens[$0].id }
        if let onScreen = candidates.first(where: { $0.screen.id == sid }) { return [onScreen.node.id] }
        return candidates.first.map { [$0.node.id] } ?? []
    }

    mutating func edit(_ line: RFSLine) {
        let targets = resolveTarget(line)
        guard !targets.isEmpty else { warnings.append("EDIT: nothing selected to change"); return }
        // Positional text after the target replaces the main text ("EDIT selected "New title"").
        var positional = line.positional
        if let f = line.tokens.first, RFSParser.isQuoted("\"\(f)\""), positional.first == f { positional.removeFirst() }
        if let second = line.tokens.dropFirst().first, RFSCompiler.type(for: (line.tokens.first ?? "").uppercased()) != nil, positional.first == second { positional.removeFirst() }
        for id in targets {
            var newActions: [Action] = []
            if let a = line.actions, !a.isEmpty { newActions = compileActions(a) }
            let replaceActions = line.flags.contains("replace")
            var attrs = line.attributes
            if let text = positional.first, attrs["text"] == nil, attrs["title"] == nil { attrs["title"] = text }
            let flags = line.flags.filter { !["selected", "this", "it", "last", "all", "replace"].contains($0) }
            guard var node = project.node(id: id) else { continue }
            apply(attributes: attrs, flags: flags, to: &node)
            if !newActions.isEmpty {
                let event = eventKind(attrs["on"], for: node.type)
                if replaceActions || node.handlers(for: event).isEmpty {
                    node.events.removeAll { $0.event == event }
                    node.events.append(EventHandler(event: event, actions: newActions))
                } else {
                    for a in newActions { node.addAction(a, on: event) }
                }
            }
            finalizeBinding(&node)
            let updated = node
            project.updateNode(id) { $0 = updated }
            lastNodeID = id
            changes.append(ChangeRecord(.updatedNode, "Updated \(node.displayName)", screenID: project.screenContaining(nodeID: id)?.id, nodeID: id))
        }
    }

    mutating func delete(_ line: RFSLine) {
        let first = line.tokens.first?.lowercased() ?? ""
        if first == "screen" || first == "page" {
            let name = line.tokens.dropFirst().joined(separator: " ")
            if let s = project.screen(named: name) {
                project.removeScreen(id: s.id)
                changes.append(ChangeRecord(.removedNode, "Deleted the \(s.name) screen"))
            }
            return
        }
        for id in resolveTarget(line) {
            guard project.locate(id)?.isRoot == false else { continue }
            if let removed = project.removeNode(id) {
                changes.append(ChangeRecord(.removedNode, "Removed \(removed.displayName)", nodeID: id))
            }
        }
    }

    // MARK: Polish

    mutating func polish() {
        // Drop empty containers created by this script (models sometimes forget to indent children).
        for id in createdContainers {
            guard let n = project.node(id: id), n.children.isEmpty, n.repeatSource == nil, n.type != .zstack else { continue }
            if [.vstack, .hstack, .card, .grid, .scroll, .section, .groupBox, .form, .pager].contains(n.type) {
                project.removeNode(id)
                created.removeAll { $0 == id }
                changes.removeAll { $0.nodeID == id }
            } else if n.type == .list {
                // An empty list is replaced by sample rows so it never renders blank.
                project.updateNode(id) { $0.children = ComponentRegistry.spec(for: .list).makeNode().children }
            }
        }
        // Wide rows of stat cards read better as a 2-column grid.
        for id in createdContainers {
            guard let n = project.node(id: id), n.type == .hstack, n.children.count > 3, n.children.allSatisfy({ $0.type == .statCard }) else { continue }
            project.updateNode(id) { node in
                node.type = .grid
                node.props = ["columns": 2, "spacing": 12]
            }
        }
        // Avoid repeating the navigation title as the first text element.
        for i in project.screens.indices {
            guard let first = project.screens[i].root.children.first, first.type == .text,
                  first.string("text").lowercased() == project.screens[i].title.lowercased(), created.contains(first.id) else { continue }
            project.screens[i].root.children.removeFirst()
            created.removeAll { $0 == first.id }
        }
        // Repeated lists need a row template that reads from `item`.
        for id in created {
            guard let n = project.node(id: id), n.repeatSource != nil, n.children.isEmpty else { continue }
            project.updateNode(id) { node in
                node.children = [Node(type: .listRow, props: ["title": "{{item.title ?? item}}", "subtitle": "{{item.subtitle ?? ''}}", "icon": "circle.fill"])]
            }
        }
    }
}

// MARK: - Well-known places (offline geocoding for MAP "Paris")

public enum Places {
    public struct Place { public let name: String; public let lat: Double; public let lon: Double }
    static let table: [String: Place] = {
        let raw: [(String, Double, Double)] = [
            ("Paris", 48.8566, 2.3522), ("London", 51.5074, -0.1278), ("New York", 40.7128, -74.0060), ("Tokyo", 35.6762, 139.6503),
            ("Manila", 14.5995, 120.9842), ("San Francisco", 37.7749, -122.4194), ("Los Angeles", 34.0522, -118.2437), ("Sydney", -33.8688, 151.2093),
            ("Singapore", 1.3521, 103.8198), ("Dubai", 25.2048, 55.2708), ("Rome", 41.9028, 12.4964), ("Berlin", 52.5200, 13.4050),
            ("Madrid", 40.4168, -3.7038), ("Barcelona", 41.3874, 2.1686), ("Amsterdam", 52.3676, 4.9041), ("Seoul", 37.5665, 126.9780),
            ("Hong Kong", 22.3193, 114.1694), ("Bangkok", 13.7563, 100.5018), ("Cebu", 10.3157, 123.8854), ("Toronto", 43.6532, -79.3832),
            ("Chicago", 41.8781, -87.6298), ("Miami", 25.7617, -80.1918), ("Seattle", 47.6062, -122.3321), ("Austin", 30.2672, -97.7431),
            ("Mexico City", 19.4326, -99.1332), ("Rio de Janeiro", -22.9068, -43.1729), ("Cape Town", -33.9249, 18.4241), ("Cairo", 30.0444, 31.2357),
            ("Istanbul", 41.0082, 28.9784), ("Mumbai", 19.0760, 72.8777), ("Delhi", 28.7041, 77.1025), ("Beijing", 39.9042, 116.4074),
            ("Shanghai", 31.2304, 121.4737), ("Apple Park", 37.3349, -122.0090), ("Cupertino", 37.3230, -122.0322), ("Eiffel Tower", 48.8584, 2.2945),
            ("Times Square", 40.7580, -73.9855), ("Central Park", 40.7829, -73.9654), ("Golden Gate Bridge", 37.8199, -122.4783),
            ("Makati", 14.5547, 121.0244), ("BGC", 14.5509, 121.0503), ("Quezon City", 14.6760, 121.0437), ("Kyoto", 35.0116, 135.7681),
            ("Osaka", 34.6937, 135.5023), ("Lisbon", 38.7223, -9.1393), ("Vienna", 48.2082, 16.3738), ("Prague", 50.0755, 14.4378),
        ]
        var d: [String: Place] = [:]
        for (n, la, lo) in raw { d[n.lowercased()] = Place(name: n, lat: la, lon: lo) }
        return d
    }()

    public static func lookup(_ raw: String) -> Place? {
        let q = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = table[q] { return p }
        return table.first { q.contains($0.key) }?.value
    }
}
