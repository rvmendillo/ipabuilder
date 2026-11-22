import SwiftUI
import ReyForgeCore

/// The element tree of the current screen: select, reorder, nest, hide and delete.
struct LayersPanel: View {
    @ObservedObject var editor: EditorModel
    @State private var collapsed: Set<String> = []

    struct Row: Identifiable {
        let node: Node
        let depth: Int
        let parentID: String?
        var id: String { node.id }
    }

    func rows(_ node: Node, depth: Int, parent: String?) -> [Row] {
        var out = [Row(node: node, depth: depth, parentID: parent)]
        if !collapsed.contains(node.id) {
            for c in node.children { out += rows(c, depth: depth + 1, parent: node.id) }
        }
        return out
    }

    var body: some View {
        if let screen = editor.currentScreen {
            let all = rows(screen.root, depth: 0, parent: nil)
            List {
                Section {
                    ForEach(all) { row in
                        LayerRow(editor: editor, row: row, isCollapsed: collapsed.contains(row.id)) {
                            if collapsed.contains(row.id) { collapsed.remove(row.id) } else { collapsed.insert(row.id) }
                        }
                        .moveDisabled(row.parentID == nil)
                    }
                    .onMove { from, to in move(all, from: from, to: to) }
                } header: {
                    HStack {
                        Label(screen.name, systemImage: "iphone")
                        Spacer()
                        Text("\(all.count - 1) element\(all.count - 1 == 1 ? "" : "s")").font(.caption)
                    }
                } footer: {
                    Text("Drag rows to reorder. Swipe for more. Use ⇥ to nest an element inside the container above it.")
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.defaultMinListRowHeight, 38)
        }
    }

    /// Moving in the flattened tree: the element lands before the row it is dropped on (same parent).
    func move(_ all: [Row], from: IndexSet, to: Int) {
        guard let i = from.first, all.indices.contains(i) else { return }
        let moving = all[i]
        if to >= all.count {
            if let root = editor.currentScreen?.root { editor.mutate("Move") { p in _ = p.move(moving.id, to: root.id, at: root.children.count) } }
            return
        }
        let target = all[to]
        guard target.id != moving.id, let parentID = target.parentID, let parent = editor.project.node(id: parentID),
              let idx = parent.children.firstIndex(where: { $0.id == target.id }) else { return }
        editor.mutate("Move") { p in _ = p.move(moving.id, to: parentID, at: idx) }
    }
}

struct LayerRow: View {
    @ObservedObject var editor: EditorModel
    let row: LayersPanel.Row
    let isCollapsed: Bool
    let toggle: () -> Void

    var node: Node { row.node }
    var spec: ComponentSpec { ComponentRegistry.spec(for: node.type) }
    var selected: Bool { editor.selection == node.id }

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 14, height: 1)
            if !node.children.isEmpty {
                Button(action: toggle) { Image(systemName: isCollapsed ? "chevron.right" : "chevron.down").font(.caption2.weight(.bold)) }
                    .buttonStyle(.borderless).frame(width: 14)
            } else {
                Color.clear.frame(width: 14, height: 1)
            }
            Image(systemName: spec.symbol).foregroundStyle(selected ? Color.white : Color.accentColor).frame(width: 22)
            Text(row.parentID == nil ? "Screen" : node.displayName).lineLimit(1).font(.subheadline)
                .foregroundStyle(selected ? .white : .primary)
            Spacer(minLength: 4)
            if node.visibleIf != nil { Image(systemName: "eye.slash").font(.caption2).foregroundStyle(selected ? .white : .secondary) }
            if node.repeatSource != nil { Image(systemName: "repeat").font(.caption2).foregroundStyle(selected ? .white : .secondary) }
            if !node.events.isEmpty { Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(selected ? .white : .orange) }
            if node.locked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(selected ? .white : .secondary) }
        }
        .contentShape(Rectangle())
        .onTapGesture { editor.selection = node.id }
        .listRowBackground(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
        .accessibilityIdentifier("layer.\(node.id)")
        .swipeActions(edge: .trailing) {
            if row.parentID != nil {
                Button(role: .destructive) { editor.delete(node.id) } label: { Label("Delete", systemImage: "trash") }
                Button { editor.duplicate(node.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(.blue)
            }
        }
        .swipeActions(edge: .leading) {
            if row.parentID != nil {
                Button { indent() } label: { Label("Nest", systemImage: "increase.indent") }.tint(.purple)
                Button { outdent() } label: { Label("Unnest", systemImage: "decrease.indent") }.tint(.indigo)
            }
        }
        .contextMenu {
            if row.parentID != nil {
                Button { editor.moveBy(node.id, -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                Button { editor.moveBy(node.id, 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                Button { indent() } label: { Label("Nest in container above", systemImage: "increase.indent") }
                Button { outdent() } label: { Label("Move out of container", systemImage: "decrease.indent") }
                Button { editor.wrap(node.id, in: .vstack) } label: { Label("Wrap in Stack", systemImage: "square.3.layers.3d") }
                Button { editor.duplicate(node.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { editor.delete(node.id) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    /// Moves the node into the previous sibling (when it's a container).
    func indent() {
        guard let parentID = row.parentID, let parent = editor.project.node(id: parentID),
              let idx = parent.children.firstIndex(where: { $0.id == node.id }), idx > 0 else { editor.flash("Nothing above to nest into"); return }
        let target = parent.children[idx - 1]
        guard ComponentRegistry.canContain(target.type, node.type) else { editor.flash("\(target.displayName) can't contain this"); return }
        editor.mutate("Nest") { p in _ = p.move(node.id, to: target.id, at: target.children.count) }
    }

    /// Moves the node out to its grandparent, right after its current parent.
    func outdent() {
        guard let parentID = row.parentID, let grand = editor.project.parent(of: parentID),
              let idx = grand.children.firstIndex(where: { $0.id == parentID }) else { editor.flash("Already at the top level"); return }
        editor.mutate("Unnest") { p in _ = p.move(node.id, to: grand.id, at: idx + 1) }
    }
}
