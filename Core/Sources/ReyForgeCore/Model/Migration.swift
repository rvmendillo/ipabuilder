import Foundation

/// Imports projects saved by ReyForge 2.x (UserDefaults key `reyforge.projects.v2`).
/// 2.x placed components absolutely on a 390×844 canvas (center x/y + size); they are
/// converted into a draggable Free Layout container so nothing moves.
public enum LegacyMigration {
    public static let legacyDefaultsKey = "reyforge.projects.v2"

    public static func migrate(data: Data) -> [Project] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list: [[String: Any]]
        if let a = json as? [[String: Any]] { list = a }
        else if let o = json as? [String: Any], let a = o["projects"] as? [[String: Any]] { list = a }
        else if let o = json as? [String: Any] { list = [o] }
        else { return [] }
        return list.compactMap(migrate(project:))
    }

    static func str(_ d: [String: Any], _ keys: String...) -> String? {
        for k in keys { if let s = d[k] as? String, !s.isEmpty { return s } }
        return nil
    }

    static func num(_ d: [String: Any], _ keys: String...) -> Double? {
        for k in keys {
            if let n = d[k] as? Double { return n }
            if let n = d[k] as? Int { return Double(n) }
            if let s = d[k] as? String, let n = Double(s) { return n }
        }
        return nil
    }

    public static func migrate(project d: [String: Any]) -> Project? {
        let name = str(d, "name", "title") ?? "Imported App"
        var project = Project(name: name, bundleID: str(d, "bundleIdentifier", "bundleID") ?? BundleID.suggest(for: name))
        if let idString = str(d, "id"), let uuid = UUID(uuidString: idString) { project.id = uuid }
        project.templateID = "legacy-v2"

        // Variables were a flat key/value map.
        if let vars = d["variables"] as? [String: Any] {
            for (k, v) in vars.sorted(by: { $0.key < $1.key }) {
                let value = Value(any: v)
                let kind: ValueKind = value.numberValue != nil && !(v is String) ? .number : (v is Bool ? .bool : .text)
                project.ensureVariable(k, type: kind, initial: value)
            }
        } else if let vars = d["variables"] as? [[String: Any]] {
            for v in vars {
                if let k = str(v, "key", "name") { project.ensureVariable(k, type: .text, initial: Value(any: v["value"])) }
            }
        }

        var canvas = Node(type: .zstack, name: "Imported canvas", props: ["clipsContent": true],
                          style: Style(width: .fill, height: .fixed(844), background: .solid("background")))
        let components = d["components"] as? [[String: Any]] ?? []
        var extraScreens: [String] = []
        for c in components {
            guard var node = convert(component: c, project: &project, extraScreens: &extraScreens) else { continue }
            let w = num(c, "width") ?? 200
            let h = num(c, "height") ?? 44
            let x = num(c, "x") ?? 195
            let y = num(c, "y") ?? 200
            node.style.width = .fixed(w)
            node.style.height = .fixed(h)
            node.style.offsetX = max(0, x - w / 2)
            node.style.offsetY = max(0, y - h / 2)
            canvas.children.append(node)
        }

        var home = Screen(name: "Home", title: name, icon: "house.fill", largeTitle: false)
        home.root.style.padding = Insets(all: 0)
        home.root.children = [canvas]
        project.addScreen(home)
        for s in extraScreens where project.screen(named: s) == nil {
            var screen = Screen(name: s, icon: "doc.text")
            screen.root.children = [
                Node(type: .text, props: ["text": .string(s)], style: Style(font: FontSpec(style: "largeTitle", weight: "bold"))),
                Node(type: .button, props: ["title": "Back", "icon": "chevron.backward", "variant": "bordered"], events: [EventHandler(event: .tap, actions: [.back()])]),
            ]
            project.addScreen(screen)
        }

        if let w = d["widget"] as? [String: Any] {
            project.widget.enabled = (w["enabled"] as? Bool) ?? false
            project.widget.title = str(w, "displayName", "title") ?? project.widget.title
            project.widget.subtitle = str(w, "subtitle") ?? project.widget.subtitle
            project.widget.symbol = str(w, "symbol") ?? project.widget.symbol
            if let fam = str(w, "family")?.lowercased() {
                project.widget.family = fam.contains("medium") ? .medium : (fam.contains("large") ? .large : .small)
            }
        }
        project.normalize()
        return project
    }

    static func convert(component c: [String: Any], project: inout Project, extraScreens: inout [String]) -> Node? {
        let kind = (str(c, "kind", "type") ?? "text")
        let text = str(c, "text", "title") ?? ""
        let detail = str(c, "detail") ?? ""
        var node: Node
        switch kind {
        case "button": node = Node(type: .button, props: ["title": .string(text.isEmpty ? "Button" : text), "fullWidth": false, "variant": "prominent", "size": "regular"])
        case "textField": node = Node(type: .textField, props: ["placeholder": .string(text)])
        case "secureField": node = Node(type: .secureField, props: ["placeholder": .string(text)])
        case "textEditor": node = Node(type: .textEditor, props: ["placeholder": .string(text)])
        case "symbol": node = Node(type: .icon, props: ["symbol": .string(text.isEmpty ? "star.fill" : text)])
        case "toggle": node = Node(type: .toggle, props: ["title": .string(text)])
        case "slider": node = Node(type: .slider, props: ["title": .string(text)])
        case "stepper": node = Node(type: .stepper, props: ["title": .string(text)])
        case "picker":
            let options = (c["options"] as? [String]) ?? detail.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            node = Node(type: .picker, props: ["title": .string(text), "options": .array((options.isEmpty ? ["One", "Two"] : options).map { .string($0) }), "variant": "menu"])
        case "datePicker": node = Node(type: .datePicker, props: ["title": .string(text)])
        case "colorPicker": node = Node(type: .colorPicker, props: ["title": .string(text)])
        case "progress": node = Node(type: .progress, props: ["label": .string(text), "value": .number(Double(detail) ?? 0.5)])
        case "gauge": node = Node(type: .gauge, props: ["label": .string(text), "value": .number(Double(detail) ?? 50)])
        case "divider": node = Node(type: .divider)
        case "spacer": node = Node(type: .spacer)
        case "navigationLink":
            node = Node(type: .navLink, props: ["title": .string(text), "destination": .string(detail.isEmpty ? "Detail" : detail)])
            extraScreens.append(detail.isEmpty ? "Detail" : detail)
        case "scrollView", "vStack", "hStack", "zStack", "section":
            node = Node(type: .card, props: [:], style: Style(padding: Insets(all: 12), background: .solid("surface")),
                        children: text.isEmpty ? [] : [Node(type: .text, props: ["text": .string(text)])])
        case "capsule": node = Node(type: .shape, props: ["shape": "capsule", "fill": "accent"])
        case "roundedRectangle", "rectangle": node = Node(type: .shape, props: ["shape": "roundedRectangle", "fill": "accent"])
        case "circle": node = Node(type: .shape, props: ["shape": "circle", "fill": "accent"])
        case "webView": node = Node(type: .web, props: ["url": .string(detail.isEmpty ? (text.hasPrefix("http") ? text : "https://www.apple.com") : detail)])
        case "shareLink": node = Node(type: .shareLink, props: ["title": .string(text.isEmpty ? "Share" : text), "item": .string(detail)])
        case "image": node = Node(type: .image, props: ["source": .string(detail.isEmpty ? text : detail)])
        case "list": node = Node(type: .list, children: (detail.isEmpty ? text : detail).split(separator: ",").map { Node(type: .listRow, props: ["title": .string(String($0).trimmingCharacters(in: .whitespaces))]) })
        case "map": node = Node(type: .map, props: ["title": .string(text)])
        default:
            node = Node(type: .text, props: ["text": .string(text.isEmpty ? detail : text)])
        }
        if let fs = num(c, "fontSize") { node.style.font = FontSpec(size: fs) }
        if let r = num(c, "cornerRadius") { node.style.cornerRadius = r }

        var actions: [Action] = []
        for a in (c["actions"] as? [[String: Any]]) ?? [] {
            let key = str(a, "key", "actionKey") ?? ""
            let value = str(a, "value", "actionValue") ?? ""
            switch str(a, "kind", "type") ?? "" {
            case "showAlert": actions.append(.alert(key.isEmpty ? "Alert" : key, value))
            case "navigate":
                let dest = value.isEmpty ? (key.isEmpty ? "Detail" : key) : value.replacingOccurrences(of: "reyforge://", with: "").capitalized
                extraScreens.append(dest)
                actions.append(.navigate(dest))
            case "setVariable":
                let v = project.ensureVariable(key.isEmpty ? "value" : key, type: .text)
                actions.append(.set(v, value))
            case "toggleVariable":
                let v = project.ensureVariable(key.isEmpty ? "flag" : key, type: .bool)
                actions.append(.toggle(v))
            case "increment":
                let v = project.ensureVariable(key.isEmpty ? "count" : key, type: .number)
                actions.append(.increment(v))
            case "decrement":
                let v = project.ensureVariable(key.isEmpty ? "count" : key, type: .number)
                actions.append(.decrement(v))
            case "openURL": actions.append(.open(value.isEmpty ? key : value))
            case "saveLocal":
                let v = project.ensureVariable(key.isEmpty ? "saved" : key, type: .text, persist: true)
                if let i = project.variables.firstIndex(where: { $0.name == v }) { project.variables[i].persist = true }
                actions.append(.set(v, value))
            case "apiGET":
                let v = project.ensureVariable(key.isEmpty ? "response" : key, type: .object)
                actions.append(.api(value, into: v))
            case "copyText": actions.append(.copy(value.isEmpty ? key : value))
            default: break
            }
        }
        if !actions.isEmpty {
            let event: EventKind = [.toggle, .slider, .stepper, .picker, .datePicker, .colorPicker, .textField].contains(node.type) ? .change : .tap
            node.events = [EventHandler(event: event, actions: actions)]
        }
        return node
    }
}
