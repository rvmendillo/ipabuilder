import SwiftUI
import ReyForgeCore

// MARK: - Design-mode hooks (implemented by the builder canvas)

@MainActor
protocol DesignHandler: AnyObject {
    func select(_ nodeID: String)
    func contextActions(for nodeID: String) -> [DesignMenuAction]
}

struct DesignMenuAction: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let destructive: Bool
    let run: () -> Void
}

private struct DesignHandlerKey: EnvironmentKey { static let defaultValue: DesignHandler? = nil }
private struct PaletteKey: EnvironmentKey { static let defaultValue = ThemePalette(theme: Theme(), dark: false) }
private struct InListKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var designHandler: DesignHandler? {
        get { self[DesignHandlerKey.self] }
        set { self[DesignHandlerKey.self] = newValue }
    }
    var palette: ThemePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    /// True when rendered as a row of a native List/Form (rows then skip their own card chrome).
    var inNativeList: Bool {
        get { self[InListKey.self] }
        set { self[InListKey.self] = newValue }
    }
}

/// Frames of rendered nodes, collected by the builder to draw selection, handles and drop targets.
struct NodeBoundsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Node view

struct NodeView: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    @Environment(\.designHandler) var design

    var body: some View {
        let _ = store.revision
        let visible = store.isVisible(node, scope: scope)
        if visible || store.mode == .design {
            content
                .modifier(NodeStyle(node: node, palette: palette))
                .opacity(visible ? 1 : 0.35)
                .modifier(DesignChrome(node: node, enabled: store.mode == .design, isContainer: ComponentRegistry.spec(for: node.type).isContainer))
                .modifier(NodeEvents(node: node, scope: scope, enabled: store.mode == .run))
                .modifier(MarginModifier(margin: node.style.margin))
        }
    }

    @ViewBuilder var content: some View {
        if ComponentRegistry.spec(for: node.type).isContainer {
            ContainerView(node: node, scope: scope)
        } else {
            LeafView(node: node, scope: scope)
                .allowsHitTesting(store.mode == .run)
        }
    }
}

/// Renders a node's children, repeating them for each item of `repeatSource`.
struct ChildrenView: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore

    var body: some View {
        if let items = store.items(for: node, scope: scope) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                let s = scope.with(["item": pair.element, "index": .number(Double(pair.offset))])
                ForEach(node.children) { child in NodeView(node: child, scope: s) }
            }
        } else {
            ForEach(node.children) { child in NodeView(node: child, scope: scope) }
        }
    }
}

// MARK: - Common modifiers

struct NodeStyle: ViewModifier {
    let node: Node
    let palette: ThemePalette

    func body(content: Content) -> some View {
        let s = node.style
        let radius = s.cornerRadius ?? (s.background != nil && node.type != .text ? palette.theme.cornerRadius : 0)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .font(FontMapper.font(s.font))
            .modifier(ForegroundModifier(color: s.foreground.map { palette.color($0) }))
            .padding(EdgeInsets(top: s.padding?.top ?? 0, leading: s.padding?.leading ?? 0, bottom: s.padding?.bottom ?? 0, trailing: s.padding?.trailing ?? 0))
            .modifier(FrameModifier(style: s, defaultAlignment: node.type == .text ? HAlign(rawValue: node.string("alignment")) : nil))
            .background {
                if let bg = s.background { palette.fill(bg).clipShape(shape) }
            }
            .overlay {
                if let bc = s.borderColor, (s.borderWidth ?? 0) > 0 { shape.strokeBorder(palette.color(bc), lineWidth: s.borderWidth ?? 1) }
            }
            .modifier(ClipModifier(clip: s.clip, radius: radius, clipToRadius: s.cornerRadius != nil && node.type == .image))
            .modifier(ShadowModifier(shadow: s.shadow, palette: palette))
            .modifier(GlassModifier(enabled: s.glass == true, radius: radius))
            .opacity(s.opacity ?? 1)
            .rotationEffect(.degrees(s.rotation ?? 0))
            .scaleEffect(s.scale ?? 1)
            .blur(radius: s.blur ?? 0)
            .zIndex(s.zIndex ?? 0)
    }
}

struct ForegroundModifier: ViewModifier {
    let color: Color?
    func body(content: Content) -> some View {
        if let c = color { content.foregroundStyle(c) } else { content }
    }
}

struct FrameModifier: ViewModifier {
    let style: Style
    let defaultAlignment: HAlign?

    func body(content: Content) -> some View {
        let align = (style.alignment ?? defaultAlignment ?? .leading).frameAlignment
        let w: CGFloat? = style.width?.fixedValue.map { CGFloat($0) }
        let h: CGFloat? = style.height?.fixedValue.map { CGFloat($0) }
        let fillW = style.width == .fill
        let fillH = style.height == .fill
        content
            .frame(width: w, height: h, alignment: align)
            .frame(minHeight: style.minHeight.map { CGFloat($0) }, alignment: align)
            .frame(maxWidth: fillW ? .infinity : (style.maxWidth.map { CGFloat($0) } ?? (defaultAlignment != nil && defaultAlignment != .leading ? .infinity : nil)),
                   maxHeight: fillH ? .infinity : nil, alignment: align)
    }
}

struct ClipModifier: ViewModifier {
    let clip: ClipShape?
    let radius: Double
    let clipToRadius: Bool
    func body(content: Content) -> some View {
        switch clip {
        case .circle?: content.clipShape(Circle())
        case .capsule?: content.clipShape(Capsule())
        case .rounded?: content.clipShape(RoundedRectangle(cornerRadius: max(radius, 12), style: .continuous))
        default:
            if clipToRadius { content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)) } else { content }
        }
    }
}

struct ShadowModifier: ViewModifier {
    let shadow: ShadowSpec?
    let palette: ThemePalette
    func body(content: Content) -> some View {
        if let s = shadow { content.shadow(color: palette.color(s.color, fallback: .black.opacity(0.15)), radius: s.radius, x: s.x, y: s.y) } else { content }
    }
}

struct GlassModifier: ViewModifier {
    let enabled: Bool
    let radius: Double
    func body(content: Content) -> some View {
        if enabled {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: max(radius, 16), style: .continuous))
            } else {
                content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: max(radius, 16), style: .continuous))
            }
            #else
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: max(radius, 16), style: .continuous))
            #endif
        } else {
            content
        }
    }
}

struct MarginModifier: ViewModifier {
    let margin: Insets?
    func body(content: Content) -> some View {
        if let m = margin { content.padding(EdgeInsets(top: m.top, leading: m.leading, bottom: m.bottom, trailing: m.trailing)) } else { content }
    }
}

/// Tap / long-press handlers for run mode (controls handle their own events).
struct NodeEvents: ViewModifier {
    let node: Node
    let scope: Scope
    let enabled: Bool
    @EnvironmentObject var store: RuntimeStore

    var handlesOwnTap: Bool {
        [.button, .toggle, .slider, .stepper, .picker, .datePicker, .colorPicker, .textField, .secureField, .textEditor, .searchField,
         .menu, .shareLink, .photoPicker, .link, .navLink, .listRow, .rating, .timer, .empty, .signInApple, .disclosure, .pager, .web, .map, .video, .audio].contains(node.type)
    }

    func body(content: Content) -> some View {
        let tap = node.handlers(for: .tap)
        let long = node.handlers(for: .longPress)
        if enabled && (!tap.isEmpty && !handlesOwnTap || !long.isEmpty) {
            content
                .contentShape(Rectangle())
                .onTapGesture { if !tap.isEmpty && !handlesOwnTap { store.run(tap, scope: scope) } }
                .onLongPressGesture { if !long.isEmpty { store.haptic("medium"); store.run(long, scope: scope) } }
                .task { if !node.handlers(for: .appear).isEmpty { await store.runAndWait(node.handlers(for: .appear), scope: scope) } }
        } else if enabled && !node.handlers(for: .appear).isEmpty {
            content.task { await store.runAndWait(node.handlers(for: .appear), scope: scope) }
        } else {
            content
        }
    }
}

/// In design mode: tap to select, long-press menu, and frame reporting for the canvas overlay.
struct DesignChrome: ViewModifier {
    let node: Node
    let enabled: Bool
    let isContainer: Bool
    @Environment(\.designHandler) var design

    func body(content: Content) -> some View {
        if enabled, let design = design {
            let target = Color.clear.contentShape(Rectangle()).onTapGesture { design.select(node.id) }
            Group {
                if isContainer { content.background(target) } else { content.overlay(target) }
            }
            .contextMenu {
                ForEach(design.contextActions(for: node.id)) { a in
                    Button(role: a.destructive ? .destructive : nil) { a.run() } label: { Label(a.title, systemImage: a.symbol) }
                }
            }
            .transformAnchorPreference(key: NodeBoundsKey.self, value: .bounds) { dict, anchor in dict[node.id] = anchor }
            .accessibilityIdentifier("node.\(node.id)")
        } else {
            content
        }
    }
}
