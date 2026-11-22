import SwiftUI
import ReyForgeCore

struct ScreenView: View {
    let screen: Screen
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    @Environment(\.designHandler) var design

    /// Screens whose top level holds lists/forms render as one native List (swipe actions, grouped style).
    var usesNativeList: Bool {
        screen.root.children.contains { $0.type == .list || $0.type == .form } && screen.root.repeatSource == nil
    }

    var body: some View {
        let scope = store.scope()
        content(scope)
            .background { palette.fill(screen.background ?? .solid(palette.dark ? palette.theme.darkBackground : palette.theme.background)).ignoresSafeArea() }
            .navigationTitle(Template.render(screen.title, scope: scope))
            .navigationBarTitleDisplayMode(screen.largeTitle ? .large : .inline)
            .toolbar(screen.showsNavigationBar ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ForEach(screen.toolbar) { item in
                    ToolbarItem(placement: placement(item.placement)) {
                        Button {
                            if store.mode == .design { design?.select("toolbar:" + item.id) } else { store.run(item.actions, scope: scope) }
                        } label: {
                            if item.title.isEmpty { Image(systemName: item.icon.isEmpty ? "plus" : item.icon) }
                            else if item.icon.isEmpty { Text(item.title) }
                            else { Label(item.title, systemImage: item.icon) }
                        }
                        .accessibilityIdentifier("toolbar.\(item.id)")
                    }
                }
            }
            .modifier(SearchableModifier(binding: screen.searchBinding))
            .task(id: screen.id) {
                if store.mode == .run && !screen.onAppear.isEmpty { await store.runAndWait(screen.onAppear) }
            }
    }

    @ViewBuilder func content(_ scope: Scope) -> some View {
        let root = screen.root
        if usesNativeList {
            List {
                ForEach(root.children) { child in
                    switch child.type {
                    case .list:
                        Section {
                            NativeRows(parent: child, scope: scope)
                        } header: {
                            SectionHeader(node: child, text: store.string(child, "header", scope))
                        } footer: {
                            let f = store.string(child, "footer", scope)
                            if !f.isEmpty { Text(f) }
                        }
                    case .form:
                        ForEach(child.children) { section in
                            if section.type == .section {
                                Section {
                                    NativeRows(parent: section, scope: scope)
                                } header: {
                                    SectionHeader(node: section, text: store.string(section, "header", scope), parent: child)
                                } footer: {
                                    let f = store.string(section, "footer", scope)
                                    if !f.isEmpty { Text(f) }
                                }
                            } else {
                                Section { NodeView(node: section, scope: scope).environment(\.inNativeList, true) }
                            }
                        }
                    case .section:
                        Section {
                            NativeRows(parent: child, scope: scope)
                        } header: {
                            SectionHeader(node: child, text: store.string(child, "header", scope))
                        }
                    default:
                        NodeView(node: child, scope: scope)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .modifier(ListStyleModifier(variant: listVariant))
            .scrollContentBackground(.hidden)
            .refreshable(enabled: !screen.refreshActions.isEmpty && store.mode == .run) { await store.runAndWait(screen.refreshActions) }
        } else if screen.scrolls {
            ScrollView {
                NodeView(node: root, scope: scope).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .refreshable(enabled: !screen.refreshActions.isEmpty && store.mode == .run) { await store.runAndWait(screen.refreshActions) }
        } else {
            NodeView(node: root, scope: scope).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    var listVariant: String {
        screen.root.children.first { $0.type == .list }?.string("variant") ?? "insetGrouped"
    }

    func placement(_ p: ToolbarItem.Placement) -> ToolbarItemPlacement {
        switch p {
        case .leading: return .topBarLeading
        case .trailing: return .topBarTrailing
        case .bottom: return .bottomBar
        }
    }
}

/// A native section header; in the builder it also selects the list / section it belongs to.
struct SectionHeader: View {
    let node: Node
    let text: String
    var parent: Node? = nil
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.designHandler) var design
    @Environment(\.selectedNodeID) var selectedID

    var body: some View {
        if store.mode == .design, let design = design {
            let selected = selectedID == node.id || (parent != nil && selectedID == parent?.id)
            Button { design.select(selected && parent != nil ? parent!.id : node.id) } label: {
                HStack(spacing: 6) {
                    Text(text.isEmpty ? ComponentRegistry.spec(for: node.type).title : text)
                    Image(systemName: selected ? "checkmark.circle.fill" : "slider.horizontal.3")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                ForEach(design.contextActions(for: node.id)) { a in
                    Button(role: a.destructive ? .destructive : nil) { a.run() } label: { Label(a.title, systemImage: a.symbol) }
                }
            }
            .accessibilityIdentifier("section.\(node.id)")
        } else if !text.isEmpty {
            Text(text)
        }
    }
}

/// Rows of a native list section, with swipe-to-delete wired to the row's delete actions.
struct NativeRows: View {
    let parent: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.designHandler) var design

    var rows: [(Node, Scope, Int)] {
        if let items = store.items(for: parent, scope: scope) {
            if items.isEmpty && store.mode == .design {
                let s = scope.with(["item": .object([:]), "index": .number(0)])
                return parent.children.map { ($0, s, 0) }
            }
            return items.enumerated().flatMap { i, item in parent.children.map { ($0, scope.with(["item": item, "index": .number(Double(i))]), i) } }
        }
        return parent.children.enumerated().map { ($0.element, scope, 0) }
    }

    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            let (node, s, repetition) = row
            let delete = node.handlers(for: .delete)
            NodeView(node: node, scope: s)
                .environment(\.inNativeList, true)
                .environment(\.designHandler, repetition > 0 ? nil : design)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if store.mode == .run && !delete.isEmpty {
                        Button(role: .destructive) { store.run(delete, scope: s) } label: {
                            Label(node.string("deleteLabel").isEmpty ? "Delete" : node.string("deleteLabel"), systemImage: "trash")
                        }
                    }
                }
        }
    }
}

struct ListStyleModifier: ViewModifier {
    let variant: String
    func body(content: Content) -> some View {
        switch variant {
        case "plain": content.listStyle(.plain)
        case "grouped": content.listStyle(.grouped)
        case "inset": content.listStyle(.inset)
        default: content.listStyle(.insetGrouped)
        }
    }
}

struct SearchableModifier: ViewModifier {
    let binding: String?
    @EnvironmentObject var store: RuntimeStore
    func body(content: Content) -> some View {
        if let b = binding, !b.isEmpty {
            content.searchable(text: Binding(get: { store.state.value(b).stringValue }, set: { store.setValue(b, .string($0)) }))
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder func refreshable(enabled: Bool, action: @escaping @Sendable () async -> Void) -> some View {
        if enabled { self.refreshable(action: action) } else { self }
    }
}
