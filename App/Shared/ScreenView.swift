import SwiftUI
import ReyForgeCore

struct ScreenView: View {
    let screen: Screen
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette

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
                        Button { store.run(item.actions, scope: scope) } label: {
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
                            let h = store.string(child, "header", scope)
                            if !h.isEmpty { Text(h) }
                        } footer: {
                            let f = store.string(child, "footer", scope)
                            if !f.isEmpty { Text(f) }
                        }
                        .modifier(DesignChrome(node: child, enabled: store.mode == .design, isContainer: true))
                    case .form:
                        ForEach(child.children) { section in
                            if section.type == .section {
                                Section {
                                    NativeRows(parent: section, scope: scope)
                                } header: {
                                    let h = store.string(section, "header", scope)
                                    if !h.isEmpty { Text(h) }
                                } footer: {
                                    let f = store.string(section, "footer", scope)
                                    if !f.isEmpty { Text(f) }
                                }
                                .modifier(DesignChrome(node: section, enabled: store.mode == .design, isContainer: true))
                            } else {
                                Section { NodeView(node: section, scope: scope).environment(\.inNativeList, true) }
                            }
                        }
                    case .section:
                        Section {
                            NativeRows(parent: child, scope: scope)
                        } header: {
                            let h = store.string(child, "header", scope)
                            if !h.isEmpty { Text(h) }
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

/// Rows of a native list section, with swipe-to-delete wired to the row's delete actions.
struct NativeRows: View {
    let parent: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore

    var rows: [(Node, Scope, Int)] {
        if let items = store.items(for: parent, scope: scope) {
            return items.enumerated().flatMap { i, item in parent.children.map { ($0, scope.with(["item": item, "index": .number(Double(i))]), i) } }
        }
        return parent.children.enumerated().map { ($0.element, scope, $0.offset) }
    }

    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            let (node, s, _) = row
            let delete = node.handlers(for: .delete)
            NodeView(node: node, scope: s)
                .environment(\.inNativeList, true)
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
