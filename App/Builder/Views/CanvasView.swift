import SwiftUI
import ReyForgeCore

/// The live design canvas: the real SwiftUI rendering of the current screen inside a device frame.
struct CanvasView: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var store: RuntimeStore
    @Environment(\.colorScheme) var systemScheme

    init(editor: EditorModel) {
        self.editor = editor
        self.store = editor.designStore
    }

    var dark: Bool {
        switch editor.project.theme.appearance {
        case .dark: return true
        case .light: return false
        case .system: return systemScheme == .dark
        }
    }

    var showsTabBar: Bool {
        editor.project.navigation.style == .tabs && editor.project.navigation.tabs.count >= 2 && editor.project.isTab(editor.currentScreenID)
    }

    var body: some View {
        let palette = ThemePalette(theme: editor.project.theme, dark: dark)
        GeometryReader { geo in
            let width = min(geo.size.width - 20, 430)
            let height = max(240, geo.size.height - 16)
            ZStack {
                CanvasBackdrop()
                    .contentShape(Rectangle())
                    .onTapGesture { editor.selection = nil }
                VStack(spacing: 0) {
                    if let screen = editor.currentScreen {
                        NavigationStack {
                            ScreenView(screen: screen)
                        }
                        .id(screen.id)
                        if showsTabBar { MockTabBar(editor: editor, palette: palette) }
                    }
                }
                .frame(width: width, height: height)
                .background(palette.background)
                .environmentObject(store)
                .environment(\.designHandler, editor)
                .environment(\.selectedNodeID, editor.selection)
                .environment(\.palette, palette)
                .environment(\.colorScheme, dark ? .dark : .light)
                .tint(palette.accent)
                .fontDesign(palette.fontDesign)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.primary.opacity(0.18), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { editor.canvasFrame = $0 }
                .accessibilityIdentifier("canvas")
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct CanvasBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 18
            var path = Path()
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 1.6, height: 1.6))
                    x += step
                }
                y += step
            }
            ctx.fill(path, with: .color(.secondary.opacity(0.25)))
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// A non-interactive copy of the tab bar; tapping a tab switches the screen being edited.
struct MockTabBar: View {
    @ObservedObject var editor: EditorModel
    let palette: ThemePalette

    var body: some View {
        HStack {
            ForEach(editor.project.navigation.tabs) { tab in
                Button { editor.showScreen(tab.screenID) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 19))
                        Text(tab.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(tab.screenID == editor.currentScreenID ? palette.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab.\(tab.title)")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Drop indicator and drag ghost, drawn above everything in global coordinates.
struct DragOverlay: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                if let r = editor.dropIndicator {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: max(3, r.width), height: max(3, r.height))
                        .opacity(r.width > 6 && r.height > 6 ? 0.25 : 1)
                        .position(x: r.midX - origin.x, y: r.midY - origin.y)
                        .shadow(color: Color.accentColor.opacity(0.6), radius: 4)
                }
                if let g = editor.dragGhost {
                    Label(g.title, systemImage: g.symbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                        .position(x: g.location.x - origin.x, y: g.location.y - origin.y - 34)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
