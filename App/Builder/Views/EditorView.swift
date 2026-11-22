import SwiftUI
import ReyForgeCore

/// The app editor: canvas + bottom drawer (iPhone) or sidebar (iPad).
struct EditorView: View {
    @StateObject private var editor: EditorModel
    @EnvironmentObject var library: ProjectLibrary
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.dismiss) var dismiss
    @State private var keyboardVisible = false
    let initialPrompt: String?

    init(project: Project, library: ProjectLibrary, initialPrompt: String? = nil) {
        _editor = StateObject(wrappedValue: EditorModel(project: project, library: library))
        self.initialPrompt = initialPrompt
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    EditorTopBar(editor: editor) { close() }
                    if sizeClass == .regular && geo.size.width > 900 {
                        HStack(spacing: 0) {
                            CanvasView(editor: editor)
                            Divider()
                            VStack(spacing: 0) {
                                PanelPicker(editor: editor, compact: false)
                                Divider()
                                PanelContent(editor: editor, panel: editor.panel ?? .inspect)
                            }
                            .frame(width: 400)
                            .background(Color(.systemBackground))
                        }
                    } else {
                        CanvasView(editor: editor)
                            .frame(maxHeight: .infinity)
                        // While typing, give the panel the room (the keyboard already covers the bottom).
                        if editor.selection != nil && !keyboardVisible { SelectionBar(editor: editor) }
                        if let panel = editor.panel {
                            Drawer(editor: editor, panel: panel, maxHeight: geo.size.height * 0.72)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if !keyboardVisible { PanelPicker(editor: editor, compact: true) }
                    }
                }
                DragOverlay(editor: editor)
                if let t = editor.toast {
                    Text(t)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 54)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("editor.toast")
                }
            }
            .animation(.snappy(duration: 0.25), value: editor.panel)
            .animation(.snappy(duration: 0.25), value: editor.toast)
        }
        .background(Color(.systemGroupedBackground))
        .fullScreenCover(isPresented: $editor.showPreview) {
            PreviewView(project: editor.project, assets: library.assetsFolder(for: editor.project.id))
        }
        .sheet(isPresented: $editor.showBuild) {
            BuildView(editor: editor)
        }
        .alert("Edit text", isPresented: Binding(get: { editor.quickEdit != nil }, set: { if !$0 { editor.quickEdit = nil } })) {
            TextField("Text", text: Binding(get: { editor.quickEdit?.text ?? "" }, set: { editor.quickEdit?.text = $0 }))
            Button("Save") { if let e = editor.quickEdit { editor.commitQuickEdit(e) } }
            Button("Cancel", role: .cancel) { editor.quickEdit = nil }
        }
        .onAppear {
            if let p = initialPrompt, !p.isEmpty {
                editor.panel = .ai
                let chat = editor.chat
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    chat.send(p)
                }
            }
        }
        .onDisappear { editor.saveNow() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }

    func close() {
        editor.saveNow()
        library.reload()
        library.openProject = nil
        dismiss()
    }
}

struct EditorTopBar: View {
    @ObservedObject var editor: EditorModel
    let close: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: close) { Image(systemName: "chevron.backward").font(.headline) }
                .accessibilityLabel("Projects")
                .accessibilityIdentifier("editor.back")
            Menu {
                ForEach(editor.project.screens) { s in
                    Button { editor.showScreen(s.id) } label: { Label(s.name, systemImage: s.id == editor.currentScreenID ? "checkmark" : s.icon) }
                }
                Divider()
                Button { editor.panel = .screens } label: { Label("Manage screens", systemImage: "rectangle.stack") }
            } label: {
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(editor.project.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text(editor.currentScreen?.name ?? "Screen").font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .foregroundStyle(.primary)
            }
            .accessibilityIdentifier("editor.screenMenu")
            Spacer(minLength: 4)
            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!editor.canUndo).accessibilityLabel("Undo").accessibilityIdentifier("editor.undo")
            Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!editor.canRedo).accessibilityLabel("Redo").accessibilityIdentifier("editor.redo")
            Button { editor.saveNow(); editor.showPreview = true } label: { Image(systemName: "play.fill") }
                .accessibilityLabel("Preview").accessibilityIdentifier("editor.preview")
            Button { editor.saveNow(); editor.showBuild = true } label: {
                Label("Build", systemImage: "hammer.fill").labelStyle(.titleAndIcon).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(RF.gradient))
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("editor.build")
        }
        .font(.title3)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Quick actions for the selected element.
struct SelectionBar: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        if let node = editor.selectedNode {
            let isRoot = editor.project.locate(node.id)?.isRoot == true
            HStack(spacing: 4) {
                Image(systemName: ComponentRegistry.spec(for: node.type).symbol).foregroundStyle(Color.accentColor)
                Text(isRoot ? "Screen" : node.displayName).font(.footnote.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Group {
                    if EditorModel.textKey(for: node) != nil {
                        barButton("character.cursor.ibeam", "Edit text", "sel.text") {
                            if let k = EditorModel.textKey(for: node) { editor.quickEdit = QuickEdit(nodeID: node.id, key: k, text: node.string(k)) }
                        }
                    }
                    barButton("slider.horizontal.3", "Design", "sel.inspect") { editor.panel = .inspect }
                    barButton("bolt.horizontal", "Logic", "sel.logic") { editor.panel = .logic }
                    if !isRoot {
                        barButton("arrow.up", "Move up", "sel.up") { editor.moveBy(node.id, -1) }
                        barButton("arrow.down", "Move down", "sel.down") { editor.moveBy(node.id, 1) }
                        barButton("plus.square.on.square", "Duplicate", "sel.duplicate") { editor.duplicate(node.id) }
                        barButton("arrow.up.left.square", "Select parent", "sel.parent") { editor.selectParent() }
                        barButton("trash", "Delete", "sel.delete", destructive: true) { editor.delete(node.id) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
    }

    func barButton(_ symbol: String, _ label: String, _ id: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 32, height: 30)
        }
        .foregroundStyle(destructive ? Color.red : Color.primary)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// The bottom bar choosing a panel.
struct PanelPicker: View {
    @ObservedObject var editor: EditorModel
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 2 : 6) {
            ForEach(EditorPanel.allCases) { p in
                PanelButton(panel: p, selected: editor.panel == p) {
                    if compact && editor.panel == p { editor.panel = nil } else { editor.panel = p }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct PanelButton: View {
    let panel: EditorPanel
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: panel.symbol).font(.system(size: 17, weight: .medium))
                Text(panel.title).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? AnyShapeStyle(RF.gradient) : AnyShapeStyle(Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("panel.\(panel.rawValue)")
    }
}

/// A resizable bottom drawer hosting a panel (the canvas stays visible and editable above).
struct Drawer: View {
    @ObservedObject var editor: EditorModel
    let panel: EditorPanel
    let maxHeight: CGFloat
    @GestureState private var dragDelta: CGFloat = 0

    var body: some View {
        let height = min(max(200, editor.drawerHeight - dragDelta), maxHeight)
        VStack(spacing: 0) {
            HStack {
                Text(panel.title).font(.headline)
                Spacer()
                Button { editor.panel = nil } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                    .accessibilityLabel("Close panel")
                    .accessibilityIdentifier("drawer.close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .overlay(alignment: .top) {
                Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($dragDelta) { v, state, _ in state = v.translation.height }
                    .onEnded { v in editor.drawerHeight = min(max(200, editor.drawerHeight - v.translation.height), maxHeight) }
            )
            PanelContent(editor: editor, panel: panel)
        }
        .frame(height: height)
        .background(Color(.systemBackground))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
    }
}

struct PanelContent: View {
    @ObservedObject var editor: EditorModel
    let panel: EditorPanel

    var body: some View {
        NavigationStack {
            Group {
                switch panel {
                case .add: LibraryPanel(editor: editor)
                case .layers: LayersPanel(editor: editor)
                case .inspect: InspectorPanel(editor: editor)
                case .logic: LogicPanel(editor: editor)
                case .ai: AIPanel(editor: editor)
                case .data: DataPanel(editor: editor)
                case .screens: ScreensPanel(editor: editor)
                case .brand: BrandPanel(editor: editor)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .id(panel)
    }
}

/// Runs the project exactly like the built app.
struct PreviewView: View {
    @StateObject private var store: RuntimeStore
    @Environment(\.dismiss) var dismiss

    init(project: Project, assets: URL) {
        _store = StateObject(wrappedValue: RuntimeStore(project: project, mode: .run, persistence: MemoryPersistence(), assetsDirectory: assets))
    }

    var body: some View {
        RuntimeRootView(store: store)
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 10) {
                    Button {
                        store.state.reset()
                        store.resetNavigation()
                        store.splashFinished = false
                    } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("Restart preview")
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close preview")
                        .accessibilityIdentifier("preview.close")
                }
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.trailing, 16)
                .padding(.bottom, 90)
            }
    }
}
