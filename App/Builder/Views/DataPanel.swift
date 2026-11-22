import SwiftUI
import ReyForgeCore

/// App state (variables) and REST endpoints.
struct DataPanel: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        Form {
            Section {
                ForEach(editor.project.variables) { v in
                    NavigationLink {
                        VariableEditor(editor: editor, variableID: v.id)
                    } label: {
                        HStack {
                            Image(systemName: v.type.symbol).foregroundStyle(Color.accentColor).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.name).font(.subheadline.monospaced())
                                Text(v.isComputed ? "= \(v.formula ?? "")" : preview(v)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if v.persist { Image(systemName: "externaldrive.fill").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .onDelete { idx in editor.mutate("Delete Variable") { p in p.variables.remove(atOffsets: idx) } }
                Menu {
                    ForEach(ValueKind.allCases, id: \.self) { kind in
                        Button { addVariable(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                    }
                } label: { Label("Add variable", systemImage: "plus.circle.fill") }
                .accessibilityIdentifier("data.addVariable")
            } header: {
                SectionTitle(title: "Variables", symbol: "cylinder.split.1x2")
            } footer: {
                Text("Use variables in any text as {{name}}, bind controls to them and change them with logic. Saved ones persist between launches.")
            }
            Section {
                ForEach(editor.project.apis) { api in
                    NavigationLink {
                        APIEditor(editor: editor, apiID: api.id)
                    } label: {
                        HStack {
                            Text(api.method).font(.caption.monospaced().weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.teal))
                            VStack(alignment: .leading) {
                                Text(api.name).font(.subheadline)
                                Text(api.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .onDelete { idx in editor.mutate("Delete API") { p in p.apis.remove(atOffsets: idx) } }
                Button {
                    editor.mutate("Add API") { p in
                        p.apis.append(APIEndpoint(name: "Todos", url: "https://jsonplaceholder.typicode.com/todos?_limit=10", resultVariable: p.ensureVariable("todos", type: .list)))
                    }
                } label: { Label("Add API endpoint", systemImage: "plus.circle.fill") }
            } header: {
                SectionTitle(title: "APIs", symbol: "network")
            } footer: {
                Text("Call an endpoint from logic with “API Request”. The JSON response is stored in a variable.")
            }
        }
    }

    func preview(_ v: Variable) -> String {
        let s = v.initial.jsonString(pretty: false)
        return "\(v.type.title) · \(s.count > 40 ? String(s.prefix(40)) + "…" : s)"
    }

    func addVariable(_ kind: ValueKind) {
        let base: String
        switch kind {
        case .bool: base = "isEnabled"
        case .number: base = "count"
        case .list: base = "items"
        case .date: base = "date"
        case .color: base = "color"
        case .object: base = "record"
        case .image: base = "photo"
        case .text: base = "text"
        }
        editor.mutate("Add Variable") { p in _ = p.ensureVariable(uniqueName(base, p), type: kind) }
    }

    func uniqueName(_ base: String, _ p: Project) -> String {
        var n = base, i = 2
        while p.variable(named: n) != nil { n = base + String(i); i += 1 }
        return n
    }
}

struct VariableEditor: View {
    @ObservedObject var editor: EditorModel
    let variableID: String
    @State private var name = ""
    @State private var initialText = ""
    @State private var jsonError: String?

    var variable: Variable? { editor.project.variables.first { $0.id == variableID } }

    func update(_ label: String = "Edit Variable", _ change: @escaping (inout Variable) -> Void) {
        editor.mutate(label) { p in
            if let i = p.variables.firstIndex(where: { $0.id == variableID }) { change(&p.variables[i]) }
        }
    }

    var body: some View {
        if let v = variable {
            Form {
                Section("Variable") {
                    HStack {
                        TextField("Name", text: $name)
                            .font(.body.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .onSubmit { rename(v) }
                        if name != v.name { Button("Rename") { rename(v) }.buttonStyle(.borderless) }
                    }
                    Picker("Type", selection: Binding(get: { v.type }, set: { t in update { $0.type = t; $0.initial = t.coerce($0.initial) }; loadInitial() })) {
                        ForEach(ValueKind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Toggle("Save between launches", isOn: Binding(get: { v.persist }, set: { p in update { $0.persist = p } }))
                }
                Section {
                    initialEditor(v)
                } header: { Text(v.isComputed ? "Initial value (ignored for computed)" : "Initial value") }
                Section {
                    TextField("e.g. sum(cart, \"price\")", text: Binding(get: { v.formula ?? "" }, set: { f in update { $0.formula = f.isEmpty ? nil : f } }), axis: .vertical)
                        .font(.callout.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never)
                } header: { Text("Computed formula") } footer: {
                    Text("When set, the value is always calculated from other variables.")
                }
                Section("Notes") {
                    TextField("What it's for", text: Binding(get: { v.notes }, set: { n in update { $0.notes = n } }), axis: .vertical)
                }
                Section {
                    let uses = usageCount(v.name)
                    Text(uses == 0 ? "Not used yet" : "Used in \(uses) place\(uses == 1 ? "" : "s")").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(v.name)
            .onAppear { name = v.name; loadInitial() }
        }
    }

    @ViewBuilder func initialEditor(_ v: Variable) -> some View {
        switch v.type {
        case .bool:
            Toggle("Initially on", isOn: Binding(get: { v.initial.boolValue }, set: { b in update { $0.initial = .bool(b) } }))
        case .number:
            TextField("0", value: Binding(get: { v.initial.numberValue ?? 0 }, set: { n in update { $0.initial = .number(n) } }), format: .number)
                .keyboardType(.decimalPad)
        case .list, .object:
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: $initialText)
                    .font(.caption.monospaced()).frame(minHeight: 140)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                if let e = jsonError { Text(e).font(.caption).foregroundStyle(.red) }
                Button("Apply JSON") {
                    if let parsed = Value.fromJSONString(initialText) {
                        jsonError = nil
                        update { $0.initial = $0.type.coerce(parsed) }
                    } else { jsonError = "That isn't valid JSON." }
                }
                .buttonStyle(.borderless)
            }
        case .date:
            DatePicker("Date", selection: Binding(get: { v.initial.date ?? Date() }, set: { d in update { $0.initial = .string(ISO8601DateFormatter().string(from: d)) } }))
        case .color:
            ColorField(title: "Color", token: Binding(get: { v.initial.stringValue }, set: { c in update { $0.initial = .string(c ?? "#007AFF") } }), palette: editor.palette, allowsNone: false)
        case .text, .image:
            TextField("Value", text: Binding(get: { v.initial.stringValue }, set: { s in update { $0.initial = .string(s) } }), axis: .vertical)
        }
    }

    func loadInitial() {
        if let v = variable { initialText = v.initial.jsonString(pretty: true) }
    }

    func rename(_ v: Variable) {
        let clean = Variable.sanitize(name)
        guard clean != v.name else { name = clean; return }
        editor.mutate("Rename Variable") { p in p.renameVariable(v.name, to: clean) }
        name = clean
    }

    func usageCount(_ name: String) -> Int {
        guard let d = try? editor.project.jsonData(pretty: false), let s = String(data: d, encoding: .utf8) else { return 0 }
        return max(0, s.components(separatedBy: name).count - 2)
    }
}

struct APIEditor: View {
    @ObservedObject var editor: EditorModel
    let apiID: String
    @State private var testing = false
    @State private var response = ""

    var api: APIEndpoint? { editor.project.apis.first { $0.id == apiID } }

    func binding<T>(_ kp: WritableKeyPath<APIEndpoint, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { api?[keyPath: kp] ?? fallback }, set: { v in
            editor.mutate("Edit API") { p in if let i = p.apis.firstIndex(where: { $0.id == apiID }) { p.apis[i][keyPath: kp] = v } }
        })
    }

    var body: some View {
        Form {
            Section("Request") {
                TextField("Name", text: binding(\.name, ""))
                Picker("Method", selection: binding(\.method, "GET")) {
                    ForEach(["GET", "POST", "PUT", "PATCH", "DELETE"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("https://api.example.com/items", text: binding(\.url, ""), axis: .vertical)
                    .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never).font(.callout.monospaced())
            }
            Section {
                LinesEditor(title: "Headers", hint: "One per line: Name: value",
                            lines: Binding(get: { (api?.headers ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" } }, set: { lines in
                                var h: [String: String] = [:]
                                for l in lines { let parts = l.split(separator: ":", maxSplits: 1); if parts.count == 2 { h[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces) } }
                                binding(\.headers, [:]).wrappedValue = h
                            }))
                TextField("JSON body (supports {{variables}})", text: binding(\.body, ""), axis: .vertical)
                    .font(.caption.monospaced()).lineLimit(2...8).autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            Section("Response") {
                VariablePicker(editor: editor, title: "Save to", kind: .list, selection: binding(\.resultVariable, nil), suggestedName: "results")
                TextField("Path inside the JSON (e.g. data.items)", text: binding(\.resultPath, ""))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            Section {
                Button { Task { await test() } } label: {
                    HStack { Label("Send test request", systemImage: "paperplane"); if testing { Spacer(); ProgressView() } }
                }
                .disabled(testing)
                if !response.isEmpty {
                    ScrollView(.horizontal) { Text(response).font(.caption2.monospaced()).textSelection(.enabled) }
                        .frame(maxHeight: 220)
                }
            }
        }
        .navigationTitle(api?.name ?? "API")
    }

    func test() async {
        guard let api = api else { return }
        testing = true
        defer { testing = false }
        let client = URLSessionHTTPClient()
        let scope = editor.designStore.scope()
        let url = Template.render(api.url, scope: scope)
        let body = api.body.isEmpty ? nil : Template.render(api.body, scope: scope).data(using: .utf8)
        var headers = api.headers
        if body != nil && headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        do {
            let r = try await client.send(HTTPRequest(url: url, method: api.method, headers: headers, body: body))
            var v = r.json
            if !api.resultPath.isEmpty { v = v.value(atPath: api.resultPath) }
            let text = v.jsonString(pretty: true)
            response = "HTTP \(r.status)\n" + (text.count > 4000 ? String(text.prefix(4000)) + "\n…" : text)
        } catch {
            response = "Error: \(error.localizedDescription)"
        }
    }
}
