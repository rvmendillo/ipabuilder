import SwiftUI
import ReyForgeCore

/// Visual logic: event handlers of the selected element, built from actions with nested branches.
struct LogicPanel: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        if let node = editor.selectedNode {
            NodeLogicView(editor: editor, nodeID: node.id)
        } else if let screen = editor.currentScreen {
            Form {
                Section {
                    Text("Select an element on the canvas to add logic to it, or set up what happens on this screen.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    ActionListEditor(editor: editor, actions: Binding(get: { editor.project.screen(id: screen.id)?.onAppear ?? [] }, set: { v in editor.updateScreen(screen.id, label: "Edit Logic") { $0.onAppear = v } }))
                } header: { SectionTitle(title: "When \(screen.name) appears", symbol: "eye") }
                Section {
                    ActionListEditor(editor: editor, actions: Binding(get: { editor.project.screen(id: screen.id)?.refreshActions ?? [] }, set: { v in editor.updateScreen(screen.id, label: "Edit Logic") { $0.refreshActions = v } }))
                } header: { SectionTitle(title: "Pull to refresh", symbol: "arrow.clockwise") }
            }
        }
    }
}

struct NodeLogicView: View {
    @ObservedObject var editor: EditorModel
    let nodeID: String

    var node: Node? { editor.project.node(id: nodeID) }

    func actions(for event: EventKind) -> Binding<[Action]> {
        Binding(get: { editor.project.node(id: nodeID)?.events.first { $0.event == event }?.actions ?? [] }, set: { new in
            editor.update(nodeID, label: "Edit Logic") { n in
                if let i = n.events.firstIndex(where: { $0.event == event }) {
                    if new.isEmpty { n.events.remove(at: i) } else { n.events[i].actions = new }
                } else if !new.isEmpty {
                    n.events.append(EventHandler(event: event, actions: new))
                }
            }
        })
    }

    var body: some View {
        if let node = node {
            let spec = ComponentRegistry.spec(for: node.type)
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.horizontal.fill").foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(RF.gradient, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading) {
                            Text(node.displayName).font(.headline)
                            Text("Choose what happens when people interact with it.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(spec.events.isEmpty ? [EventKind.tap] : spec.events, id: \.self) { event in
                    Section {
                        ActionListEditor(editor: editor, actions: actions(for: event))
                    } header: {
                        SectionTitle(title: event.title, symbol: event.symbol)
                    }
                }
                Section {
                    ForEach(LogicRecipe.all) { recipe in
                        Button { recipe.apply(editor, nodeID, spec.events.first ?? .tap) } label: {
                            Label(recipe.title, systemImage: recipe.symbol)
                        }
                        .accessibilityIdentifier("recipe.\(recipe.id)")
                    }
                } header: {
                    SectionTitle(title: "Quick logic", symbol: "wand.and.stars")
                } footer: {
                    Text("Recipes add ready-made actions (and the variables they need) to \(spec.events.first?.title ?? "On Tap").")
                }
            }
        }
    }
}

/// Ready-made logic snippets.
struct LogicRecipe: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let build: (inout Project) -> [Action]

    func apply(_ editor: EditorModel, _ nodeID: String, _ event: EventKind) {
        editor.mutate("Add \(title)") { p in
            let actions = build(&p)
            p.updateNode(nodeID) { n in for a in actions { n.addAction(a, on: event) } }
        }
        editor.flash("Added “\(title)”")
    }

    static let all: [LogicRecipe] = [
        LogicRecipe(id: "navigate", title: "Open another screen", symbol: "arrow.right.square") { p in
            let target = p.screens.count > 1 ? p.screens[1].id : (p.screens.first?.id ?? "")
            return [.navigate(target)]
        },
        LogicRecipe(id: "toast", title: "Show a confirmation", symbol: "text.bubble") { _ in [.haptic("success"), .toast("Saved!")] },
        LogicRecipe(id: "count", title: "Count taps", symbol: "plus.circle") { p in
            let v = p.ensureVariable("tapCount", type: .number)
            return [.increment(v)]
        },
        LogicRecipe(id: "toggle", title: "Toggle a setting", symbol: "switch.2") { p in
            let v = p.ensureVariable("isOn", type: .bool)
            return [.toggle(v), .toast("{{isOn ? \"On\" : \"Off\"}}", style: "info")]
        },
        LogicRecipe(id: "add", title: "Add an item to a list", symbol: "text.badge.plus") { p in
            let v = p.ensureVariable("items", type: .list)
            return [.append(v, item: "{\"title\": \"New item {{count(items) + 1}}\", \"done\": false}"), .haptic("light")]
        },
        LogicRecipe(id: "confirm", title: "Confirm, then delete", symbol: "trash") { p in
            let v = p.ensureVariable("items", type: .list)
            return [.confirm("Delete this item?", "This can't be undone.", confirmLabel: "Delete", destructive: true, then: [.remove(v, index: "{{index}}"), .toast("Deleted", style: "info")])]
        },
        LogicRecipe(id: "validate", title: "Validate an email", symbol: "checkmark.shield") { p in
            let v = p.ensureVariable("email", type: .text)
            return [.validate("isEmail(\(v))", message: "Please enter a valid email address.", then: [.toast("Welcome!")])]
        },
        LogicRecipe(id: "api", title: "Load data from an API", symbol: "network") { p in
            let v = p.ensureVariable("todos", type: .list)
            return [.api("https://jsonplaceholder.typicode.com/todos?_limit=8", into: v, then: [.toast("Loaded {{count(todos)}} items", style: "info")], otherwise: [.toast("Couldn't load data", style: "error")])]
        },
        LogicRecipe(id: "remind", title: "Schedule a reminder", symbol: "bell.badge") { _ in [.notify("Reminder", "Don't forget to check back!", after: 10), .toast("Reminder set for 10 seconds", style: "info")] },
    ]
}

// MARK: - Action lists

struct ActionListEditor: View {
    @ObservedObject var editor: EditorModel
    @Binding var actions: [Action]

    var body: some View {
        ForEach(actions) { action in
            NavigationLink {
                ActionEditor(editor: editor, action: binding(for: action))
            } label: {
                ActionRow(action: action, project: editor.project)
            }
            .contextMenu {
                Button { if let i = actions.firstIndex(where: { $0.id == action.id }) { actions.insert(action.clonedWithNewIDs(), at: i + 1) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button { toggleEnabled(action) } label: { Label(action.enabled ? "Disable" : "Enable", systemImage: action.enabled ? "pause.circle" : "play.circle") }
                Button(role: .destructive) { actions.removeAll { $0.id == action.id } } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .onDelete { actions.remove(atOffsets: $0) }
        .onMove { actions.move(fromOffsets: $0, toOffset: $1) }
        AddActionMenu(editor: editor) { actions.append($0) }
    }

    func binding(for action: Action) -> Binding<Action> {
        Binding(get: { actions.first { $0.id == action.id } ?? action }, set: { new in
            if let i = actions.firstIndex(where: { $0.id == action.id }) { actions[i] = new }
        })
    }

    func toggleEnabled(_ a: Action) {
        if let i = actions.firstIndex(where: { $0.id == a.id }) { actions[i].enabled.toggle() }
    }
}

struct ActionRow: View {
    let action: Action
    let project: Project

    var body: some View {
        let spec = ActionRegistry.spec(for: action.kind)
        HStack(spacing: 10) {
            Image(systemName: spec.symbol)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color(spec.category), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(ActionRegistry.describe(action) { project.screenName($0) }).font(.subheadline).lineLimit(2)
                let nested = action.then.count + action.otherwise.count
                if nested > 0 {
                    Text("\(nested) nested action\(nested == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .opacity(action.enabled ? 1 : 0.45)
        }
    }

    func color(_ category: String) -> Color {
        switch category {
        case "Navigation": return .blue
        case "Feedback": return .orange
        case "Data": return .purple
        case "Logic": return .pink
        case "Network": return .teal
        default: return .gray
        }
    }
}

struct AddActionMenu: View {
    @ObservedObject var editor: EditorModel
    let add: (Action) -> Void

    var body: some View {
        Menu {
            ForEach(ActionRegistry.categories, id: \.self) { category in
                Section(category) {
                    ForEach(ActionRegistry.all.filter { $0.category == category }, id: \.kind) { spec in
                        Button { add(makeAction(spec)) } label: { Label(spec.title, systemImage: spec.symbol) }
                    }
                }
            }
        } label: {
            Label("Add action", systemImage: "plus.circle.fill")
        }
        .accessibilityIdentifier("logic.addAction")
    }

    func makeAction(_ spec: ActionSpec) -> Action {
        var a = Action(kind: spec.kind)
        for p in spec.params where !p.defaultValue.isNull { a.params[p.key] = p.defaultValue }
        let p = editor.project
        for param in spec.params {
            switch param.kind {
            case .screen:
                let other = p.screens.first { $0.id != editor.currentScreenID } ?? p.screens.first
                if let s = other { a.params[param.key] = .string(s.id) }
            case .variable:
                if let v = p.variables.first { a.params[param.key] = .string(v.name) }
            case .listVariable:
                if let v = p.variables.first(where: { $0.type == .list }) { a.params[param.key] = .string(v.name) }
            default: break
            }
        }
        switch spec.kind {
        case .toast: a.params["message"] = "Done!"
        case .alert: a.params["title"] = "Hello"
        case .confirm: a.params["title"] = "Are you sure?"
        case .condition: a.params["condition"] = "true"
        case .openURL: a.params["url"] = "https://apple.com"
        case .share, .copy: a.params["text"] = "Check out this app!"
        case .notify: a.params["title"] = "Reminder"
        default: break
        }
        return a
    }
}

/// Full-screen list of actions (used for screen and toolbar logic).
struct ActionListScreen: View {
    @ObservedObject var editor: EditorModel
    let title: String
    @Binding var actions: [Action]

    var body: some View {
        Form {
            Section {
                ActionListEditor(editor: editor, actions: $actions)
            } footer: {
                Text("Actions run top to bottom. Swipe to delete, long-press for more.")
            }
        }
        .navigationTitle(title)
        .toolbar { EditButton() }
    }
}

// MARK: - Action editor

struct ActionEditor: View {
    @ObservedObject var editor: EditorModel
    @Binding var action: Action

    var spec: ActionSpec { ActionRegistry.spec(for: action.kind) }

    func param(_ key: String) -> Binding<Value> {
        Binding(get: { action.params[key] ?? .null }, set: { v in
            var a = action
            if v.isNull || (v.stringValue.isEmpty && !(v.boolValue)) { a.params.removeValue(forKey: key) } else { a.params[key] = v }
            action = a
        })
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: spec.symbol).font(.title3).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(RF.gradient, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading) {
                        Text(spec.title).font(.headline)
                        Text(spec.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Enabled", isOn: Binding(get: { action.enabled }, set: { v in var a = action; a.enabled = v; action = a }))
            }
            if !spec.params.isEmpty {
                Section("Settings") {
                    ForEach(spec.params, id: \.key) { p in
                        ParamEditor(editor: editor, spec: p, value: param(p.key))
                    }
                }
            }
            if let label = spec.thenLabel {
                Section {
                    ActionListEditor(editor: editor, actions: Binding(get: { action.then }, set: { v in var a = action; a.then = v; action = a }))
                } header: { SectionTitle(title: label, symbol: "arrow.turn.down.right") }
            }
            if let label = spec.otherwiseLabel {
                Section {
                    ActionListEditor(editor: editor, actions: Binding(get: { action.otherwise }, set: { v in var a = action; a.otherwise = v; action = a }))
                } header: { SectionTitle(title: label, symbol: "arrow.uturn.down") }
            }
            Section {
                Text(ActionRegistry.describe(action) { editor.project.screenName($0) })
                    .font(.callout.monospaced()).foregroundStyle(.secondary)
            } header: { Text("Summary") }
        }
        .navigationTitle(spec.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ParamEditor: View {
    @ObservedObject var editor: EditorModel
    let spec: ParamSpec
    @Binding var value: Value

    var text: Binding<String> { Binding(get: { value.stringValue }, set: { value = .string($0) }) }

    var body: some View {
        switch spec.kind {
        case .text, .url:
            if spec.key == "endpoint" && !editor.project.apis.isEmpty {
                Picker(spec.label, selection: text) {
                    Text("Custom URL").tag("")
                    ForEach(editor.project.apis) { a in Text(a.name).tag(a.name) }
                }
            } else {
                labeled {
                    TextField(spec.placeholder.isEmpty ? spec.label : spec.placeholder, text: text)
                        .keyboardType(spec.kind == .url ? .URL : .default)
                        .textInputAutocapitalization(spec.kind == .url ? .never : .sentences)
                        .autocorrectionDisabled(spec.kind == .url)
                        .accessibilityIdentifier("param.\(spec.key)")
                }
            }
        case .multiline, .json:
            labeled {
                TextField(spec.placeholder.isEmpty ? spec.label : spec.placeholder, text: text, axis: .vertical)
                    .lineLimit(2...8)
                    .font(spec.kind == .json ? .callout.monospaced() : .body)
                    .textInputAutocapitalization(spec.kind == .json ? .never : .sentences)
                    .autocorrectionDisabled(spec.kind == .json)
            }
        case .expression:
            labeled {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(spec.placeholder.isEmpty ? spec.label : spec.placeholder, text: text, axis: .vertical)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("param.\(spec.key)")
                    ExpressionHelpers(editor: editor, wrap: spec.key != "condition") { value = .string(value.stringValue + $0) }
                }
            }
        case .variable:
            VariablePicker(editor: editor, title: spec.label, kind: .text, selection: Binding(get: { value.isNull ? nil : value.stringValue }, set: { value = $0.map { .string($0) } ?? .null }), suggestedName: "value")
        case .listVariable:
            VariablePicker(editor: editor, title: spec.label, kind: .list, selection: Binding(get: { value.isNull ? nil : value.stringValue }, set: { value = $0.map { .string($0) } ?? .null }), suggestedName: "items")
        case .screen:
            Picker(spec.label, selection: text) {
                Text("Choose…").tag("")
                ForEach(editor.project.screens) { s in Label(s.name, systemImage: s.icon).tag(s.id) }
            }
        case .number:
            HStack {
                Text(spec.label)
                Spacer()
                TextField(spec.placeholder.isEmpty ? "0" : spec.placeholder, value: Binding(get: { value.numberValue }, set: { value = $0.map { .number($0) } ?? .null }), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            }
        case .bool:
            Toggle(spec.label, isOn: Binding(get: { value.boolValue }, set: { value = .bool($0) }))
        case .options(let options):
            Picker(spec.label, selection: text) {
                ForEach(options, id: \.self) { Text(PropertyEditor.pretty($0)).tag($0) }
            }
        }
    }

    @ViewBuilder func labeled<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(spec.label + (spec.required ? " *" : "")).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
