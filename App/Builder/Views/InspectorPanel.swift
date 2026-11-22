import SwiftUI
import ReyForgeCore

/// Everything about the selected element: content, binding, layout, style, data and actions.
struct InspectorPanel: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        if let node = editor.selectedNode {
            NodeInspector(editor: editor, node: node)
        } else if let screen = editor.currentScreen {
            ScreenInspector(editor: editor, screen: screen)
        } else {
            EmptyHint(symbol: "cursorarrow.click", title: "Nothing selected", message: "Tap an element on the canvas to edit it.")
        }
    }
}

struct NodeInspector: View {
    @ObservedObject var editor: EditorModel
    let node: Node
    @State private var tab = 0

    var spec: ComponentSpec { ComponentRegistry.spec(for: node.type) }
    var isRoot: Bool { editor.project.locate(node.id)?.isRoot == true }
    var inFreeLayout: Bool { editor.project.parent(of: node.id)?.type == .zstack }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: spec.symbol).font(.title3).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(RF.gradient, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        TextField(spec.title, text: Binding(get: { node.name ?? "" }, set: { v in editor.update(node.id, label: "Edit name") { $0.name = v.isEmpty ? nil : v } }))
                            .font(.headline)
                            .accessibilityIdentifier("inspector.name")
                        Text(spec.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Picker("Section", selection: $tab) {
                    Text("Content").tag(0)
                    Text("Layout").tag(1)
                    Text("Style").tag(2)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspector.tabs")
            }
            switch tab {
            case 0: contentSections
            case 1: LayoutSections(editor: editor, node: node, inFreeLayout: inFreeLayout)
            default: StyleSections(editor: editor, node: node)
            }
            if !isRoot { actionsSection }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder var contentSections: some View {
        if !spec.properties.isEmpty {
            Section("Properties") {
                ForEach(spec.properties, id: \.key) { p in
                    PropertyEditor(editor: editor, node: node, spec: p)
                }
            }
        }
        if let kind = spec.bindable {
            Section {
                VariablePicker(editor: editor, title: "Bound variable", kind: kind, selection: Binding(get: { node.binding }, set: { v in editor.update(node.id, label: "Bind") { $0.binding = v } }), suggestedName: suggestedVariable)
            } header: {
                SectionTitle(title: "Data binding", symbol: "link")
            } footer: {
                Text("The control reads and writes this variable. Use it anywhere as {{\(node.binding ?? "name")}}.")
            }
        }
        Section {
            if spec.supportsRepeat || spec.isContainer {
                VariablePicker(editor: editor, title: "Repeat for each item in", kind: .list, selection: Binding(get: { node.repeatSource }, set: { v in editor.update(node.id, label: "Repeat") { $0.repeatSource = v } }), suggestedName: "items", allowsExpression: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Show only when").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. isLoggedIn && count > 0", text: Binding(get: { node.visibleIf ?? "" }, set: { v in editor.update(node.id, label: "Edit visibility") { $0.visibleIf = v.isEmpty ? nil : v } }))
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .font(.callout.monospaced())
                ExpressionHelpers(editor: editor) { insert in
                    editor.update(node.id, label: "Edit visibility") { $0.visibleIf = ($0.visibleIf ?? "") + insert }
                }
            }
        } header: {
            SectionTitle(title: "Data & visibility", symbol: "cylinder.split.1x2")
        } footer: {
            Text("Inside a repeated element, use {{item.title}} and {{index}}.")
        }
        Section {
            Button { editor.panel = .logic } label: {
                HStack {
                    Label(node.events.isEmpty ? "Add logic" : "Edit logic", systemImage: "bolt.horizontal.fill")
                    Spacer()
                    Text("\(node.events.reduce(0) { $0 + $1.actions.count }) actions").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    var suggestedVariable: String {
        let base = node.string("title").isEmpty ? (node.string("placeholder").isEmpty ? spec.title : node.string("placeholder")) : node.string("title")
        return Variable.sanitize(base)
    }

    var actionsSection: some View {
        Section {
            Button { editor.duplicate(node.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Menu {
                ForEach([ComponentType.vstack, .hstack, .zstack, .card, .groupBox, .scroll, .disclosure], id: \.self) { t in
                    Button(ComponentRegistry.spec(for: t).title) { editor.wrap(node.id, in: t) }
                }
            } label: { Label("Wrap in…", systemImage: "rectangle.on.rectangle") }
            if spec.isContainer && !node.children.isEmpty {
                Button { editor.unwrap(node.id) } label: { Label("Unwrap (keep children)", systemImage: "rectangle.dashed") }
            }
            Button { editor.selectParent() } label: { Label("Select parent", systemImage: "arrow.up.left.square") }
            Toggle(isOn: Binding(get: { node.locked }, set: { v in editor.update(node.id, label: "Lock") { $0.locked = v } })) {
                Label("Lock (AI won't change it)", systemImage: node.locked ? "lock.fill" : "lock.open")
            }
            Button(role: .destructive) { editor.delete(node.id) } label: { Label("Delete", systemImage: "trash") }
                .accessibilityIdentifier("inspector.delete")
        }
    }
}

// MARK: - Property editor

struct PropertyEditor: View {
    @ObservedObject var editor: EditorModel
    let node: Node
    let spec: PropertySpec

    var value: Value { node.props[spec.key] ?? spec.defaultValue }
    func set(_ v: Value?) { editor.setProp(node.id, spec.key, v) }
    var text: Binding<String> { Binding(get: { value.stringValue }, set: { set(.string($0)) }) }

    var body: some View {
        switch spec.kind {
        case .text, .url, .expression:
            VStack(alignment: .leading, spacing: 4) {
                Text(spec.label).font(.caption).foregroundStyle(.secondary)
                TextField(spec.label, text: text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(spec.kind == .url ? .URL : .default)
                    .autocorrectionDisabled(spec.kind != .text)
                    .textInputAutocapitalization(spec.kind == .text ? .sentences : .never)
                    .font(spec.kind == .expression ? .callout.monospaced() : .body)
                    .accessibilityIdentifier("prop.\(spec.key)")
                if spec.kind != .url {
                    ExpressionHelpers(editor: editor, wrap: true) { insert in set(.string(value.stringValue + insert)) }
                }
                if !spec.help.isEmpty { Text(spec.help).font(.caption2).foregroundStyle(.secondary) }
            }
        case .multiline:
            VStack(alignment: .leading, spacing: 4) {
                Text(spec.label).font(.caption).foregroundStyle(.secondary)
                TextField(spec.label, text: text, axis: .vertical)
                    .lineLimit(3...10)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("prop.\(spec.key)")
                ExpressionHelpers(editor: editor, wrap: true) { insert in set(.string(value.stringValue + insert)) }
            }
        case .bool:
            Toggle(spec.label, isOn: Binding(get: { value.boolValue }, set: { set(.bool($0)) }))
                .accessibilityIdentifier("prop.\(spec.key)")
        case .number(let mn, let mx, let st):
            NumberField(title: spec.label, value: Binding(get: { value.numberValue }, set: { set($0.map { .number($0) }) }),
                        range: (mn ?? 0)...(mx ?? max(100, (value.numberValue ?? 0) * 2)), step: st ?? 1, optional: false)
        case .options(let options):
            if options.count <= 3 && options.allSatisfy({ $0.count <= 9 }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spec.label).font(.caption).foregroundStyle(.secondary)
                    Picker(spec.label, selection: text) {
                        ForEach(options, id: \.self) { Text(Self.pretty($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } else {
                Picker(spec.label, selection: text) {
                    ForEach(options, id: \.self) { Text(Self.pretty($0)).tag($0) }
                }
                .pickerStyle(.menu)
            }
        case .color:
            ColorField(title: spec.label, token: Binding(get: { value.isNull || value.stringValue.isEmpty ? nil : value.stringValue }, set: { set($0.map { .string($0) }) }), palette: editor.palette)
        case .symbol:
            SymbolField(title: spec.label, symbol: Binding(get: { value.stringValue }, set: { set(.string($0)) }))
        case .image:
            ImageSourceEditor(editor: editor, title: spec.label, source: text)
        case .list:
            LinesEditor(title: spec.label, hint: "One option per line.", lines: Binding(get: { value.stringList }, set: { set(.array($0.map { .string($0) })) }))
        case .chartData:
            ChartDataEditor(title: spec.label, value: value) { set($0) }
        case .markers:
            LinesEditor(title: spec.label, hint: "One place per line: Name: latitude, longitude — or just an address when Geocode is on.",
                        lines: Binding(get: { value.stringValue.split(separator: ";").map { $0.replacingOccurrences(of: ":", with: ": ") } },
                                       set: { set(.string($0.map { $0.replacingOccurrences(of: ": ", with: ":") }.joined(separator: ";"))) }))
        case .screen:
            Picker(spec.label, selection: text) {
                Text("None").tag("")
                ForEach(editor.project.screens) { s in Text(s.name).tag(s.id) }
            }
        case .date:
            DatePicker(spec.label, selection: Binding(get: { value.date ?? Date() }, set: { set(.string(ISO8601DateFormatter().string(from: $0))) }))
        }
    }

    static func pretty(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isUppercase && !out.isEmpty { out += " " }
            out.append(out.isEmpty ? Character(ch.uppercased()) : ch)
        }
        return out
    }
}

/// Insert variables, item fields and functions into text.
struct ExpressionHelpers: View {
    @ObservedObject var editor: EditorModel
    var wrap = false
    let insert: (String) -> Void

    var body: some View {
        let vars = editor.project.variables
        if !vars.isEmpty || wrap {
            Menu {
                if !vars.isEmpty {
                    Section("Variables") {
                        ForEach(vars) { v in Button("\(v.name)  (\(v.type.title))") { insert(wrap ? "{{\(v.name)}}" : v.name) } }
                    }
                }
                Section("Repeated item") {
                    Button("item.title") { insert(wrap ? "{{item.title}}" : "item.title") }
                    Button("item.subtitle") { insert(wrap ? "{{item.subtitle}}" : "item.subtitle") }
                    Button("index") { insert(wrap ? "{{index + 1}}" : "index") }
                }
                Section("Functions") {
                    ForEach(["count(list)", "sum(list, \"amount\")", "currency(total)", "upper(name)", "formatDate(now(), \"MMM d\")", "round(value, 1)", "isEmail(email)"], id: \.self) { f in
                        Button(f) { insert(wrap ? "{{\(f)}}" : f) }
                    }
                }
            } label: {
                Label("Insert value", systemImage: "curlybraces").font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }
}

struct ImageSourceEditor: View {
    @ObservedObject var editor: EditorModel
    let title: String
    @Binding var source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("https://… or symbol:star.fill", text: $source)
                .textFieldStyle(.roundedBorder).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
            HStack {
                PhotoImportButton(title: "Choose photo") { data in
                    let id = editor.library.storeAsset(data, projectID: editor.project.id)
                    source = "asset:" + id
                }
                Spacer()
                Menu {
                    Button("Random photo") { source = "https://picsum.photos/seed/\(IDGen.short(length: 5))/800/600" }
                    Button("SF Symbol") { source = "symbol:photo.artframe" }
                    Button("Clear") { source = "" }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }
}

struct ChartDataEditor: View {
    let title: String
    let value: Value
    let set: (Value) -> Void

    var isBound: Bool { value.stringValue.contains("{{") || (Value.fromJSONString(value.stringValue) != nil && value.stringValue.hasPrefix("[")) }

    var body: some View {
        if isBound || value.arrayValue.count > 0 && !value.stringValue.contains(":") {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                TextField("{{sales}}", text: Binding(get: { value.stringValue }, set: { set(.string($0)) }))
                    .textFieldStyle(.roundedBorder).font(.callout.monospaced())
                Button("Use static values") { set(.string("Mon:4,Tue:7,Wed:5")) }.font(.caption).buttonStyle(.borderless)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                LinesEditor(title: title, hint: "One point per line: Label: value. Or bind a list with {{variable}}.",
                            lines: Binding(get: { value.stringValue.split(separator: ",").map { $0.replacingOccurrences(of: ":", with: ": ") } },
                                           set: { set(.string($0.map { $0.replacingOccurrences(of: ": ", with: ":").trimmingCharacters(in: .whitespaces) }.joined(separator: ","))) }))
                Button("Bind to a list variable") { set(.string("{{items}}")) }.font(.caption).buttonStyle(.borderless)
            }
        }
    }
}

/// Choose or create a variable (or type an expression).
struct VariablePicker: View {
    @ObservedObject var editor: EditorModel
    let title: String
    let kind: ValueKind
    @Binding var selection: String?
    var suggestedName = "value"
    var allowsExpression = false
    @State private var newName = ""
    @State private var creating = false

    var candidates: [Variable] {
        editor.project.variables.filter { kind == .text ? true : $0.type == kind || (kind == .list && $0.type == .object) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(title, selection: Binding(get: { selection ?? "" }, set: { v in
                if v == "__new__" { newName = editor.project.variables.contains { $0.name == suggestedName } ? suggestedName + "2" : suggestedName; creating = true }
                else { selection = v.isEmpty ? nil : v }
            })) {
                Text("None").tag("")
                ForEach(candidates) { v in Text(v.name).tag(v.name) }
                if let s = selection, !s.isEmpty, !candidates.contains(where: { $0.name == s }) { Text(s).tag(s) }
                Text("New variable…").tag("__new__")
            }
            if allowsExpression, let s = selection, !s.isEmpty, !candidates.contains(where: { $0.name == s }) {
                TextField("Expression", text: Binding(get: { s }, set: { selection = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder).font(.callout.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never)
            }
        }
        .alert("New \(kind.title.lowercased()) variable", isPresented: $creating) {
            TextField("Name", text: $newName).autocorrectionDisabled().textInputAutocapitalization(.never)
            Button("Create") {
                var name = ""
                editor.mutate("Add Variable") { p in name = p.ensureVariable(newName, type: kind) }
                selection = name
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Layout

struct LayoutSections: View {
    @ObservedObject var editor: EditorModel
    let node: Node
    let inFreeLayout: Bool

    func style<T>(_ kp: WritableKeyPath<Style, T>, _ label: String = "Edit layout") -> Binding<T> {
        Binding(get: { node.style[keyPath: kp] }, set: { v in editor.update(node.id, label: label) { $0.style[keyPath: kp] = v } })
    }

    var body: some View {
        Section {
            DimensionField(title: "Width", dimension: style(\.width))
            DimensionField(title: "Height", dimension: style(\.height), maxValue: 900)
            NumberField(title: "Minimum height", value: style(\.minHeight), range: 0...600)
            NumberField(title: "Maximum width", value: style(\.maxWidth), range: 40...800)
            NumberField(title: "Aspect ratio", value: style(\.aspectRatio), range: 0.25...4, step: 0.05)
        } header: { SectionTitle(title: "Size", symbol: "arrow.up.left.and.arrow.down.right") }
        Section {
            InsetsField(title: "Padding", insets: style(\.padding))
            InsetsField(title: "Margin", insets: style(\.margin))
            Picker("Alignment", selection: Binding(get: { node.style.alignment ?? .leading }, set: { v in editor.update(node.id, label: "Edit layout") { $0.style.alignment = v } })) {
                Text("Leading").tag(HAlign.leading)
                Text("Center").tag(HAlign.center)
                Text("Trailing").tag(HAlign.trailing)
            }
            .pickerStyle(.segmented)
        } header: { SectionTitle(title: "Spacing", symbol: "rectangle.inset.filled") }
        Section {
            if inFreeLayout {
                NumberField(title: "X", value: style(\.offsetX), range: 0...400, optional: false)
                NumberField(title: "Y", value: style(\.offsetY), range: 0...800, optional: false)
            } else {
                NumberField(title: "Offset X", value: style(\.offsetX), range: -200...200)
                NumberField(title: "Offset Y", value: style(\.offsetY), range: -200...200)
            }
            NumberField(title: "Layer order (z-index)", value: style(\.zIndex), range: -10...10)
            NumberField(title: "Rotation", value: style(\.rotation), range: -180...180, unit: "°")
            NumberField(title: "Scale", value: style(\.scale), range: 0.2...3, step: 0.05)
        } header: { SectionTitle(title: inFreeLayout ? "Position (free layout)" : "Position", symbol: "move.3d") } footer: {
            Text(inFreeLayout ? "Drag the move handle on the canvas to position this freely." : "Drag the move handle on the canvas to reorder or move into another container.")
        }
    }
}

// MARK: - Style

struct StyleSections: View {
    @ObservedObject var editor: EditorModel
    let node: Node

    func style<T>(_ kp: WritableKeyPath<Style, T>, _ label: String = "Edit style") -> Binding<T> {
        Binding(get: { node.style[keyPath: kp] }, set: { v in editor.update(node.id, label: label) { $0.style[keyPath: kp] = v } })
    }

    var font: Binding<FontSpec> {
        Binding(get: { node.style.font ?? FontSpec() }, set: { v in
            editor.update(node.id, label: "Edit font") { $0.style.font = (v == FontSpec()) ? nil : v }
        })
    }

    var body: some View {
        let palette = editor.palette
        Section {
            FillField(title: "Background", fill: style(\.background), palette: palette)
            ColorField(title: "Text & icon color", token: style(\.foreground), palette: palette)
            NumberField(title: "Opacity", value: style(\.opacity), range: 0...1, step: 0.05)
            Toggle("Liquid Glass", isOn: Binding(get: { node.style.glass == true }, set: { v in editor.update(node.id, label: "Edit style") { $0.style.glass = v ? true : nil } }))
        } header: { SectionTitle(title: "Fill", symbol: "paintbrush") }
        Section {
            Picker("Text style", selection: Binding(get: { font.wrappedValue.style ?? "" }, set: { v in font.wrappedValue.style = v.isEmpty ? nil : v })) {
                Text("Default").tag("")
                ForEach(FontSpec.textStyles, id: \.self) { Text(PropertyEditor.pretty($0)).tag($0) }
            }
            NumberField(title: "Custom size", value: Binding(get: { font.wrappedValue.size }, set: { font.wrappedValue.size = $0 }), range: 8...96)
            Picker("Weight", selection: Binding(get: { font.wrappedValue.weight ?? "" }, set: { v in font.wrappedValue.weight = v.isEmpty ? nil : v })) {
                Text("Default").tag("")
                ForEach(FontSpec.weights, id: \.self) { Text(PropertyEditor.pretty($0)).tag($0) }
            }
            Picker("Design", selection: Binding(get: { font.wrappedValue.design ?? "" }, set: { v in font.wrappedValue.design = v.isEmpty ? nil : v })) {
                Text("Theme").tag("")
                ForEach(FontSpec.designs, id: \.self) { Text(PropertyEditor.pretty($0)).tag($0) }
            }
            Toggle("Italic", isOn: Binding(get: { font.wrappedValue.italic == true }, set: { font.wrappedValue.italic = $0 ? true : nil }))
        } header: { SectionTitle(title: "Typography", symbol: "textformat") }
        Section {
            NumberField(title: "Corner radius", value: style(\.cornerRadius), range: 0...60)
            Picker("Clip shape", selection: Binding(get: { node.style.clip ?? ClipShape.none }, set: { (v: ClipShape) in editor.update(node.id, label: "Edit style") { $0.style.clip = (v == ClipShape.none) ? nil : v } })) {
                ForEach(ClipShape.allCases, id: \.self) { Text(PropertyEditor.pretty($0.rawValue)).tag($0) }
            }
            ColorField(title: "Border color", token: style(\.borderColor), palette: palette)
            NumberField(title: "Border width", value: style(\.borderWidth), range: 0...12, step: 0.5)
            Picker("Shadow", selection: Binding(get: { shadowName(node.style.shadow) }, set: { v in
                editor.update(node.id, label: "Edit style") { n in
                    switch v { case "small": n.style.shadow = .small; case "medium": n.style.shadow = .medium; case "large": n.style.shadow = .large; default: n.style.shadow = nil }
                }
            })) {
                Text("None").tag("none"); Text("Small").tag("small"); Text("Medium").tag("medium"); Text("Large").tag("large")
                if shadowName(node.style.shadow) == "custom" { Text("Custom").tag("custom") }
            }
            NumberField(title: "Blur", value: style(\.blur), range: 0...30)
        } header: { SectionTitle(title: "Shape & effects", symbol: "square.on.circle") }
        Section {
            Button("Reset all styles", role: .destructive) { editor.update(node.id, label: "Reset style") { $0.style = ComponentRegistry.spec(for: node.type).defaultStyle } }
        }
    }

    func shadowName(_ s: ShadowSpec?) -> String {
        guard let s = s else { return "none" }
        if s == .small { return "small" }
        if s == .medium { return "medium" }
        if s == .large { return "large" }
        return "custom"
    }
}

// MARK: - Screen inspector

struct ScreenInspector: View {
    @ObservedObject var editor: EditorModel
    let screen: Screen

    var body: some View {
        Form {
            ScreenSettingsSections(editor: editor, screen: screen)
        }
    }
}

struct ScreenSettingsSections: View {
    @ObservedObject var editor: EditorModel
    let screen: Screen

    func binding<T>(_ kp: WritableKeyPath<Screen, T>, _ label: String = "Edit Screen") -> Binding<T> {
        Binding(get: { editor.project.screen(id: screen.id)?[keyPath: kp] ?? screen[keyPath: kp] }, set: { v in editor.updateScreen(screen.id, label: label) { $0[keyPath: kp] = v } })
    }

    var body: some View {
        Section {
            TextField("Name", text: binding(\.name)).accessibilityIdentifier("screen.name")
            TextField("Navigation title", text: binding(\.title))
            SymbolField(title: "Tab icon", symbol: binding(\.icon))
            Toggle("Navigation bar", isOn: binding(\.showsNavigationBar))
            Toggle("Large title", isOn: binding(\.largeTitle))
            Toggle("Scrolls", isOn: binding(\.scrolls))
            FillField(title: "Background", fill: binding(\.background), palette: editor.palette)
        } header: { SectionTitle(title: "Screen", symbol: "iphone") }
        Section {
            Toggle("Show in tab bar", isOn: Binding(get: { editor.project.isTab(screen.id) }, set: { v in
                editor.mutate("Edit Tabs") { p in
                    p.setTab(screen.id, enabled: v)
                    if v && p.navigation.tabs.count >= 2 { p.navigation.style = .tabs }
                }
            }))
            Button("Make this the first screen") { editor.mutate("Set Initial Screen") { $0.navigation.initialScreenID = screen.id } }
                .disabled(editor.project.navigation.initialScreenID == screen.id)
            VariablePicker(editor: editor, title: "Search bar edits", kind: .text, selection: binding(\.searchBinding), suggestedName: "query")
        } header: { SectionTitle(title: "Navigation", symbol: "rectangle.split.3x1") }
        Section {
            ForEach(Array((editor.project.screen(id: screen.id)?.toolbar ?? []).enumerated()), id: \.element.id) { i, item in
                NavigationLink {
                    ToolbarItemEditor(editor: editor, screenID: screen.id, itemID: item.id)
                } label: {
                    Label(item.title.isEmpty ? item.icon : item.title, systemImage: item.icon.isEmpty ? "plus" : item.icon)
                }
            }
            .onDelete { idx in editor.updateScreen(screen.id, label: "Remove Toolbar Item") { $0.toolbar.remove(atOffsets: idx) } }
            Button { editor.updateScreen(screen.id, label: "Add Toolbar Item") { $0.toolbar.append(ScreenToolbarItem(title: "", icon: "plus")) } } label: {
                Label("Add toolbar button", systemImage: "plus.circle")
            }
        } header: { SectionTitle(title: "Toolbar", symbol: "menubar.rectangle") }
        Section {
            NavigationLink {
                ActionListScreen(editor: editor, title: "On appear", actions: binding(\.onAppear, "Edit Logic"))
            } label: { Label("When the screen appears (\(screen.onAppear.count))", systemImage: "eye") }
            NavigationLink {
                ActionListScreen(editor: editor, title: "Pull to refresh", actions: binding(\.refreshActions, "Edit Logic"))
            } label: { Label("Pull to refresh (\(screen.refreshActions.count))", systemImage: "arrow.clockwise") }
        } header: { SectionTitle(title: "Screen logic", symbol: "bolt.horizontal") }
        Section("Notes") {
            TextField("Notes for you or the AI", text: binding(\.notes), axis: .vertical).lineLimit(2...6)
        }
    }
}

struct ToolbarItemEditor: View {
    @ObservedObject var editor: EditorModel
    let screenID: String
    let itemID: String

    var item: ScreenToolbarItem? { editor.project.screen(id: screenID)?.toolbar.first { $0.id == itemID } }

    func binding<T>(_ kp: WritableKeyPath<ScreenToolbarItem, T>, fallback: T) -> Binding<T> {
        Binding(get: { item?[keyPath: kp] ?? fallback }, set: { v in
            editor.updateScreen(screenID, label: "Edit Toolbar") { s in
                if let i = s.toolbar.firstIndex(where: { $0.id == itemID }) { s.toolbar[i][keyPath: kp] = v }
            }
        })
    }

    var body: some View {
        Form {
            Section("Button") {
                TextField("Title (optional)", text: binding(\.title, fallback: ""))
                SymbolField(title: "Icon", symbol: binding(\.icon, fallback: "plus"))
                Picker("Placement", selection: binding(\.placement, fallback: .trailing)) {
                    ForEach(ScreenToolbarItem.Placement.allCases, id: \.self) { Text(PropertyEditor.pretty($0.rawValue)).tag($0) }
                }
            }
            Section("When tapped") {
                ActionListEditor(editor: editor, actions: binding(\.actions, fallback: []))
            }
        }
        .navigationTitle("Toolbar button")
    }
}
