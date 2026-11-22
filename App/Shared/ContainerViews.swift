import SwiftUI
import ReyForgeCore

struct ContainerView: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette

    var spacing: CGFloat { CGFloat(store.number(node, "spacing", scope) ?? 12) }

    var body: some View {
        switch node.type {
        case .vstack:
            VStack(alignment: hAlign(node.string("alignment")), spacing: spacing) { ChildrenView(node: node, scope: scope) }
                .frame(maxWidth: node.style.width == nil && node.string("alignment") == "center" ? .infinity : nil)
        case .hstack:
            HStack(alignment: vAlign(node.string("alignment")), spacing: spacing) {
                if store.bool(node, "equalWidths", scope) {
                    ChildrenView(node: node, scope: scope).frame(maxWidth: .infinity)
                } else {
                    ChildrenView(node: node, scope: scope)
                }
            }
        case .zstack:
            FreeLayoutView(node: node, scope: scope)
        case .scroll:
            CarouselView(node: node, scope: scope, spacing: spacing)
        case .grid:
            let cols = max(1, Int(store.number(node, "columns", scope) ?? 2))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: cols), alignment: .leading, spacing: spacing) {
                ChildrenView(node: node, scope: scope)
            }
        case .card:
            VStack(alignment: hAlign(node.string("alignment")), spacing: CGFloat(store.number(node, "spacing", scope) ?? 8)) {
                ChildrenView(node: node, scope: scope)
            }
            .frame(maxWidth: .infinity, alignment: hAlign(node.string("alignment")) == .center ? .center : (hAlign(node.string("alignment")) == .trailing ? .trailing : .leading))
        case .groupBox:
            GroupBox {
                VStack(alignment: .leading, spacing: 8) { ChildrenView(node: node, scope: scope) }.frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                let icon = node.string("icon")
                if icon.isEmpty { Text(store.string(node, "title", scope)) } else { Label(store.string(node, "title", scope), systemImage: icon) }
            }
        case .disclosure:
            DisclosureNode(node: node, scope: scope)
        case .pager:
            PagerNode(node: node, scope: scope)
        case .list, .form, .section:
            GroupedListView(node: node, scope: scope)
        case .menu:
            MenuNode(node: node, scope: scope)
        default:
            VStack(alignment: .leading, spacing: spacing) { ChildrenView(node: node, scope: scope) }
        }
    }

    func hAlign(_ s: String) -> HorizontalAlignment { s == "center" ? .center : (s == "trailing" ? .trailing : .leading) }
    func vAlign(_ s: String) -> VerticalAlignment { s == "top" ? .top : (s == "bottom" ? .bottom : .center) }
}

/// ZStack where each child sits at its offset — drag them anywhere in the builder.
struct FreeLayoutView: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(node.children) { child in
                NodeView(node: child, scope: scope)
                    .fixedSize(horizontal: child.style.width == nil, vertical: child.style.height == nil)
                    .offset(x: CGFloat(child.style.offsetX ?? 0), y: CGFloat(child.style.offsetY ?? 0))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .clipped(antialiased: store.bool(node, "clipsContent", scope))
    }
}

struct CarouselView: View {
    let node: Node
    let scope: Scope
    let spacing: CGFloat
    @EnvironmentObject var store: RuntimeStore

    var body: some View {
        let horizontal = store.string(node, "axis", scope) != "vertical"
        let paging = store.bool(node, "paging", scope)
        ScrollView(horizontal ? .horizontal : .vertical, showsIndicators: store.bool(node, "showsIndicators", scope)) {
            Group {
                if horizontal {
                    LazyHStack(alignment: .top, spacing: spacing) { ChildrenView(node: node, scope: scope) }
                } else {
                    LazyVStack(alignment: .leading, spacing: spacing) { ChildrenView(node: node, scope: scope) }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 2)
        }
        .scrollTargetBehavior(paging ? AnyScrollTargetBehavior(.viewAligned) : AnyScrollTargetBehavior(.none))
    }
}

struct AnyScrollTargetBehavior: ScrollTargetBehavior {
    enum Kind { case none, viewAligned }
    let kind: Kind
    init(_ k: Kind) { kind = k }
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        if kind == .viewAligned { ViewAlignedScrollTargetBehavior().updateTarget(&target, context: context) }
    }
}

struct DisclosureNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @State private var localExpanded: Bool?

    var body: some View {
        let initial = store.bool(node, "expanded", scope)
        let expanded: Binding<Bool> = node.binding != nil
            ? store.boolBinding(node.binding, initial: initial, node: node, scope: scope)
            : Binding(get: { localExpanded ?? initial }, set: { localExpanded = $0 })
        DisclosureGroup(isExpanded: expanded) {
            VStack(alignment: .leading, spacing: 8) { ChildrenView(node: node, scope: scope) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Text(store.string(node, "title", scope)).font(.headline)
        }
    }
}

struct PagerNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @State private var page = 0

    var pages: [(Node, Scope)] {
        if let items = store.items(for: node, scope: scope) {
            return items.enumerated().flatMap { i, item in node.children.map { ($0, scope.with(["item": item, "index": .number(Double(i))])) } }
        }
        return node.children.map { ($0, scope) }
    }

    var body: some View {
        let list = pages
        TabView(selection: Binding(get: { page }, set: { page = $0; if let b = node.binding { store.setValue(b, .number(Double($0))) }; store.fire(.change, node: node, scope: scope.with("value", .number(Double($0)))) })) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, pair in
                NodeView(node: pair.0, scope: pair.1).frame(maxWidth: .infinity, maxHeight: .infinity).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: store.bool(node, "showsIndicators", scope) ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        .frame(minHeight: 200)
        .task(id: store.number(node, "autoAdvance", scope) ?? 0) {
            let seconds = store.number(node, "autoAdvance", scope) ?? 0
            guard seconds > 0, store.mode == .run, !list.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                withAnimation { page = (page + 1) % max(1, list.count) }
            }
        }
    }
}

struct MenuNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore

    var body: some View {
        let title = store.string(node, "title", scope)
        let icon = node.string("icon")
        Menu {
            ForEach(node.children) { child in
                if child.type == .divider {
                    Divider()
                } else {
                    Button(role: child.string("role") == "destructive" || child.string("variant") == "destructive" ? .destructive : nil) {
                        store.run(child.handlers(for: .tap), scope: scope)
                    } label: {
                        let t = store.string(child, "title", scope)
                        if child.string("icon").isEmpty { Text(t) } else { Label(t, systemImage: child.string("icon")) }
                    }
                }
            }
        } label: {
            if icon.isEmpty { Text(title) } else if title.isEmpty { Image(systemName: icon).font(.title3) } else { Label(title, systemImage: icon) }
        }
        .menuStyle(.button)
        .modifier(MenuButtonStyle(variant: node.string("variant")))
        .allowsHitTesting(store.mode == .run)
    }
}

struct MenuButtonStyle: ViewModifier {
    let variant: String
    func body(content: Content) -> some View {
        switch variant {
        case "prominent": content.buttonStyle(.borderedProminent)
        case "plain": content.buttonStyle(.plain)
        default: content.buttonStyle(.bordered)
        }
    }
}

/// Lists, forms and sections nested inside other content (screen-level ones render as native List/Form).
struct GroupedListView: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    @Environment(\.inNativeList) var inNativeList

    var body: some View {
        if inNativeList {
            // Inside a native List the parent provides sections.
            VStack(alignment: .leading, spacing: 0) { ChildrenView(node: node, scope: scope) }
        } else if node.type == .form {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(node.children) { child in
                    if child.type == .section { NodeView(node: child, scope: scope) } else { GroupCard(rows: [child], scope: scope) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                let header = store.string(node, "header", scope)
                if !header.isEmpty {
                    Text(header.uppercased()).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
                }
                GroupCard(rows: nil, parent: node, scope: scope)
                let footer = store.string(node, "footer", scope)
                if !footer.isEmpty {
                    Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
                }
            }
        }
    }
}

/// An inset-grouped card of rows with separators (looks like a native List section).
struct GroupCard: View {
    var rows: [Node]?
    var parent: Node?
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette

    var expanded: [(Node, Scope)] {
        if let p = parent {
            if let items = store.items(for: p, scope: scope) {
                return items.enumerated().flatMap { i, item in p.children.map { ($0, scope.with(["item": item, "index": .number(Double(i))])) } }
            }
            return p.children.map { ($0, scope) }
        }
        return (rows ?? []).map { ($0, scope) }
    }

    var body: some View {
        let list = expanded
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, pair in
                NodeView(node: pair.0, scope: pair.1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, pair.0.type == .listRow || pair.0.type == .navLink ? 0 : 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .environment(\.inNativeList, true)
                if i < list.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: max(10, palette.theme.cornerRadius - 2), style: .continuous))
    }
}
