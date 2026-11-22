import Foundation
import SwiftUI
import ReyForgeCore

enum EditorPanel: String, CaseIterable, Identifiable {
    case add, layers, inspect, logic, ai, data, screens, brand
    var id: String { rawValue }

    var title: String {
        switch self {
        case .add: return "Add"
        case .layers: return "Layers"
        case .inspect: return "Design"
        case .logic: return "Logic"
        case .ai: return "AI"
        case .data: return "Data"
        case .screens: return "Screens"
        case .brand: return "Brand"
        }
    }

    var symbol: String {
        switch self {
        case .add: return "plus.square.on.square"
        case .layers: return "square.3.layers.3d"
        case .inspect: return "slider.horizontal.3"
        case .logic: return "bolt.horizontal"
        case .ai: return "sparkles"
        case .data: return "cylinder.split.1x2"
        case .screens: return "rectangle.stack"
        case .brand: return "paintpalette"
        }
    }
}

struct DragGhost: Equatable {
    var title: String
    var symbol: String
    var location: CGPoint
}

struct QuickEdit: Identifiable {
    let id = UUID()
    let nodeID: String
    let key: String
    var text: String
}

/// Editing session for one project: the live design canvas, selection, undo and all mutations.
@MainActor
final class EditorModel: ObservableObject, DesignHandler {
    @Published private(set) var project: Project
    @Published var currentScreenID: String
    @Published var selection: String? {
        didSet { if selection != oldValue { selectionChanged() } }
    }
    @Published var panel: EditorPanel? = nil
    @Published var drawerHeight: CGFloat = 380
    @Published var dropIndicator: CGRect?
    @Published var dragGhost: DragGhost?
    @Published var quickEdit: QuickEdit?
    @Published var toast: String?
    @Published var showPreview = false
    @Published var showBuild = false
    @Published var screenSettingsFocus: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    let designStore: RuntimeStore
    let library: ProjectLibrary
    lazy var chat = AIChatController(editor: self)

    private(set) var frames: [String: CGRect] = [:]
    var canvasFrame: CGRect = .zero
    private var undoStack: [(Project, String)] = []
    private var redoStack: [(Project, String)] = []
    private var saveTask: Task<Void, Never>?
    private var lastTarget: DropTarget?

    init(project: Project, library: ProjectLibrary) {
        var p = project
        p.normalize()
        self.project = p
        self.library = library
        currentScreenID = p.initialScreen?.id ?? p.screens.first?.id ?? ""
        designStore = RuntimeStore(project: p, mode: .design, persistence: MemoryPersistence(), assetsDirectory: library.assetsFolder(for: p.id))
    }

    var currentScreen: Screen? { project.screen(id: currentScreenID) ?? project.screens.first }
    var selectedNode: Node? { selection.flatMap { project.node(id: $0) } }
    var palette: ThemePalette { ThemePalette(theme: project.theme, dark: project.theme.appearance == .dark) }
    var context: EditorContext { EditorContext(screenID: currentScreenID, selectedNodeID: selection, lastTouchedNodeIDs: []) }

    // MARK: Mutation & history

    /// Applies a change as one undoable step.
    func mutate(_ label: String, _ change: (inout Project) -> Void) {
        var p = project
        change(&p)
        guard p != project else { return }
        commit(p, label: label)
    }

    /// Replaces the project (AI results, imports) as one undoable step.
    func replaceProject(_ p: Project, label: String) {
        var copy = p
        copy.normalize()
        guard copy != project else { return }
        commit(copy, label: label)
    }

    private var lastCommit: (label: String, time: Date, selection: String?)?

    private func commit(_ p: Project, label: String) {
        // Typing in a field produces many edits: coalesce them into one undo step.
        let coalesce = lastCommit.map { $0.label == label && $0.selection == selection && Date().timeIntervalSince($0.time) < 1.2 && label.hasPrefix("Edit") } ?? false
        if !coalesce {
            undoStack.append((project, label))
            if undoStack.count > 80 { undoStack.removeFirst() }
        }
        lastCommit = (label, Date(), selection)
        redoStack.removeAll()
        apply(p)
    }

    private func apply(_ p: Project) {
        var p = p
        p.touch()
        project = p
        designStore.update(project: p)
        if project.screen(id: currentScreenID) == nil { currentScreenID = project.initialScreen?.id ?? "" }
        if let s = selection, project.node(id: s) == nil, !s.hasPrefix("toolbar:") { selection = nil }
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        scheduleSave()
    }

    func undo() {
        guard let (previous, label) = undoStack.popLast() else { return }
        redoStack.append((project, label))
        apply(previous)
        flash("Undid \(label)")
    }

    func redo() {
        guard let (next, label) = redoStack.popLast() else { return }
        undoStack.append((project, label))
        apply(next)
        flash("Redid \(label)")
    }

    func scheduleSave() {
        saveTask?.cancel()
        let snapshot = project
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.library.save(snapshot)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        library.save(project)
    }

    func flash(_ message: String) {
        toast = message
        let current = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if self?.toast == current { self?.toast = nil }
        }
    }

    // MARK: Screens

    func showScreen(_ id: String) {
        guard project.screen(id: id) != nil else { return }
        currentScreenID = id
        selection = nil
        frames.removeAll()
    }

    @discardableResult
    func addScreen(name: String, asTab: Bool) -> String {
        var newID = ""
        mutate("Add Screen") { p in
            let screen = Screen(name: p.uniqueScreenName(name.isEmpty ? "Screen" : name), children: [
                Node(type: .text, props: ["text": .string(name.isEmpty ? "New screen" : name)], style: Style(font: FontSpec(style: "title2", weight: "bold"))),
            ])
            newID = p.addScreen(screen, asTab: asTab)
        }
        if !newID.isEmpty { showScreen(newID) }
        return newID
    }

    // MARK: Selection

    private func selectionChanged() {
        if let s = selection, s.hasPrefix("toolbar:") {
            screenSettingsFocus = String(s.dropFirst(8))
            selection = nil
            panel = .screens
        }
        // Keep the canvas showing the screen that holds the selection.
        if let s = selection, let screen = project.screenContaining(nodeID: s), screen.id != currentScreenID {
            currentScreenID = screen.id
        }
    }

    func select(_ nodeID: String) {
        if selection == nodeID, panel == nil { panel = .inspect }
        selection = nodeID
        if panel == .add { panel = .inspect }
        Haptics.selection()
    }

    func selectParent() {
        guard let s = selection, let parent = project.parent(of: s) else { return }
        selection = parent.id
    }

    // MARK: Node operations

    var insertionTarget: (containerID: String, index: Int?) {
        guard let screen = currentScreen else { return ("", nil) }
        if let s = selectedNode, let loc = project.locate(s.id) {
            if ComponentRegistry.spec(for: s.type).isContainer && s.type != .menu { return (s.id, nil) }
            if let parent = project.parent(of: s.id), let idx = loc.path.last { return (parent.id, idx + 1) }
        }
        return (screen.root.id, nil)
    }

    /// Adds a component from the library at the smartest place (inside the selected container or after the selection).
    @discardableResult
    func addComponent(_ type: ComponentType) -> String? {
        let node = ComponentRegistry.spec(for: type).makeNode()
        var target = insertionTarget
        if let container = project.node(id: target.containerID), !ComponentRegistry.canContain(container.type, type), project.locate(target.containerID)?.isRoot != true {
            if let parent = project.parent(of: container.id), let idx = project.locate(container.id)?.path.last { target = (parent.id, idx + 1) }
        }
        var inserted = false
        mutate("Add \(ComponentRegistry.spec(for: type).title)") { p in
            inserted = p.insert(node, into: target.containerID, at: target.index)
            if !inserted, let s = p.screens.firstIndex(where: { $0.id == currentScreenID }) {
                p.screens[s].root.children.append(node); inserted = true
            }
        }
        guard inserted else { return nil }
        selection = node.id
        flash("Added \(ComponentRegistry.spec(for: type).title)")
        return node.id
    }

    func delete(_ nodeID: String) {
        guard project.locate(nodeID)?.isRoot == false else { flash("The screen's root can't be deleted"); return }
        let name = project.node(id: nodeID)?.displayName ?? "element"
        mutate("Delete \(name)") { p in _ = p.removeNode(nodeID) }
        if selection == nodeID { selection = nil }
    }

    func duplicate(_ nodeID: String) {
        var newID: String?
        mutate("Duplicate") { p in newID = p.duplicateNode(nodeID) }
        if let n = newID { selection = n }
    }

    func moveBy(_ nodeID: String, _ delta: Int) {
        mutate(delta < 0 ? "Move Up" : "Move Down") { p in _ = p.moveWithinParent(nodeID, by: delta) }
    }

    func wrap(_ nodeID: String, in type: ComponentType) {
        var newID: String?
        mutate("Wrap in \(ComponentRegistry.spec(for: type).title)") { p in newID = p.wrap(nodeID, in: type) }
        if let n = newID { selection = n }
    }

    func unwrap(_ nodeID: String) {
        mutate("Unwrap") { p in _ = p.unwrap(nodeID) }
        selection = nil
    }

    func update(_ nodeID: String, label: String = "Edit", _ change: (inout Node) -> Void) {
        mutate(label) { p in p.updateNode(nodeID, change) }
    }

    func setProp(_ nodeID: String, _ key: String, _ value: Value?) {
        update(nodeID, label: "Edit \(key)") { n in
            if let v = value { n.props[key] = v } else { n.props.removeValue(forKey: key) }
        }
    }

    func updateScreen(_ id: String, label: String = "Edit Screen", _ change: (inout Screen) -> Void) {
        mutate(label) { p in
            if let i = p.screenIndex(id: id) { change(&p.screens[i]) }
        }
    }

    // MARK: DesignHandler

    func contextActions(for nodeID: String) -> [DesignMenuAction] {
        guard let node = project.node(id: nodeID) else { return [] }
        let isRoot = project.locate(nodeID)?.isRoot == true
        var actions: [DesignMenuAction] = [
            DesignMenuAction(title: "Select", symbol: "cursorarrow.rays", destructive: false) { [weak self] in self?.select(nodeID) },
            DesignMenuAction(title: "Edit Design", symbol: "slider.horizontal.3", destructive: false) { [weak self] in self?.selection = nodeID; self?.panel = .inspect },
            DesignMenuAction(title: "Add Logic", symbol: "bolt.horizontal", destructive: false) { [weak self] in self?.selection = nodeID; self?.panel = .logic },
        ]
        if let key = Self.textKey(for: node) {
            actions.insert(DesignMenuAction(title: "Edit Text", symbol: "character.cursor.ibeam", destructive: false) { [weak self] in
                self?.quickEdit = QuickEdit(nodeID: nodeID, key: key, text: node.string(key))
            }, at: 1)
        }
        if !isRoot {
            actions += [
                DesignMenuAction(title: "Duplicate", symbol: "plus.square.on.square", destructive: false) { [weak self] in self?.duplicate(nodeID) },
                DesignMenuAction(title: "Move Up", symbol: "arrow.up", destructive: false) { [weak self] in self?.moveBy(nodeID, -1) },
                DesignMenuAction(title: "Move Down", symbol: "arrow.down", destructive: false) { [weak self] in self?.moveBy(nodeID, 1) },
                DesignMenuAction(title: "Wrap in Card", symbol: "rectangle.on.rectangle", destructive: false) { [weak self] in self?.wrap(nodeID, in: .card) },
                DesignMenuAction(title: "Ask AI to Improve", symbol: "sparkles", destructive: false) { [weak self] in
                    self?.selection = nodeID
                    self?.panel = .ai
                    self?.chat.draft = "Make the selected \(ComponentRegistry.spec(for: node.type).title.lowercased()) look better"
                },
                DesignMenuAction(title: "Delete", symbol: "trash", destructive: true) { [weak self] in self?.delete(nodeID) },
            ]
        }
        return actions
    }

    static func textKey(for node: Node) -> String? {
        let keys = ComponentRegistry.spec(for: node.type).properties.map(\.key)
        for k in ["text", "title", "label", "placeholder", "message", "value"] where keys.contains(k) {
            if case .text = ComponentRegistry.spec(for: node.type).properties.first(where: { $0.key == k })?.kind ?? .bool { return k }
            if case .multiline = ComponentRegistry.spec(for: node.type).properties.first(where: { $0.key == k })?.kind ?? .bool { return k }
        }
        return nil
    }

    func reportFrame(_ nodeID: String, _ frame: CGRect) {
        frames[nodeID] = frame
    }

    private var rfFrames: [String: RFRect] {
        var out: [String: RFRect] = [:]
        for (k, f) in frames where f.width.isFinite && f.height.isFinite {
            out[k] = RFRect(x: Double(f.minX), y: Double(f.minY), width: Double(f.width), height: Double(f.height))
        }
        return out
    }

    private func dropTarget(at location: CGPoint, moving: String?, type: ComponentType) -> DropTarget? {
        guard let screen = currentScreen else { return nil }
        return DropPlanner.target(in: screen, frames: rfFrames, point: (Double(location.x), Double(location.y)), dragging: moving, draggedType: type)
    }

    private func showIndicator(_ t: DropTarget?) {
        lastTarget = t
        if let t = t {
            dropIndicator = CGRect(x: t.indicator.x, y: t.indicator.y, width: max(3, t.indicator.width), height: max(3, t.indicator.height))
        } else {
            dropIndicator = nil
        }
    }

    func moveChanged(_ nodeID: String, location: CGPoint, translation: CGSize, freeLayout: Bool) {
        guard let node = project.node(id: nodeID) else { return }
        if freeLayout, let parent = project.parent(of: nodeID), let pf = frames[parent.id], pf.contains(location) {
            showIndicator(nil)
        } else {
            showIndicator(dropTarget(at: location, moving: nodeID, type: node.type))
        }
        dragGhost = DragGhost(title: node.displayName, symbol: ComponentRegistry.spec(for: node.type).symbol, location: location)
    }

    func moveEnded(_ nodeID: String, location: CGPoint, translation: CGSize, freeLayout: Bool) {
        defer { showIndicator(nil); dragGhost = nil }
        guard let node = project.node(id: nodeID) else { return }
        if freeLayout, let parent = project.parent(of: nodeID), let pf = frames[parent.id], pf.contains(location) {
            let snap: (Double) -> Double = { v in AppSettings.shared.snapToGrid ? (v / 4).rounded() * 4 : v.rounded() }
            update(nodeID, label: "Move") { n in
                n.style.offsetX = max(0, snap((n.style.offsetX ?? 0) + Double(translation.width)))
                n.style.offsetY = max(0, snap((n.style.offsetY ?? 0) + Double(translation.height)))
            }
            return
        }
        guard abs(translation.width) + abs(translation.height) > 6, let target = dropTarget(at: location, moving: nodeID, type: node.type) else { return }
        var changed = false
        mutate("Move \(node.displayName)") { p in changed = p.applyDrop(moving: nodeID, to: target) }
        if changed { Haptics.impact() }
    }

    func resizeEnded(_ nodeID: String, size: CGSize) {
        let snap: (CGFloat) -> Double = { v in AppSettings.shared.snapToGrid ? (Double(v) / 4).rounded() * 4 : Double(v).rounded() }
        let full = canvasFrame.width > 0 && size.width >= canvasFrame.width - 40
        update(nodeID, label: "Resize") { n in
            n.style.width = full ? .fill : .fixed(max(8, snap(size.width)))
            n.style.height = .fixed(max(8, snap(size.height)))
        }
    }

    // MARK: Library drag & drop

    func libraryDragChanged(_ type: ComponentType, location: CGPoint) {
        let spec = ComponentRegistry.spec(for: type)
        dragGhost = DragGhost(title: spec.title, symbol: spec.symbol, location: location)
        showIndicator(canvasFrame.contains(location) ? dropTarget(at: location, moving: nil, type: type) : nil)
    }

    func libraryDragEnded(_ type: ComponentType, location: CGPoint) {
        defer { showIndicator(nil); dragGhost = nil }
        guard canvasFrame.contains(location), let target = dropTarget(at: location, moving: nil, type: type) else { return }
        let node = ComponentRegistry.spec(for: type).makeNode()
        var newID: String?
        mutate("Add \(ComponentRegistry.spec(for: type).title)") { p in newID = p.applyDrop(inserting: node, to: target) }
        if let id = newID {
            selection = id
            Haptics.impact()
            flash("Added \(ComponentRegistry.spec(for: type).title)")
        }
    }

    // MARK: Quick text edit

    func commitQuickEdit(_ edit: QuickEdit) {
        setProp(edit.nodeID, edit.key, .string(edit.text))
        quickEdit = nil
    }

    // MARK: Script console

    /// Runs ReyForge Script typed by the user (the same language the AI writes).
    func runScript(_ script: String) -> CompileResult {
        let result = RFSCompiler.compile(script, into: project, context: context)
        if !result.changes.isEmpty {
            replaceProject(result.project, label: "Run Script")
            if let s = result.focusScreenID { currentScreenID = s }
            if let n = result.focusNodeID { selection = n }
        }
        return result
    }
}

@MainActor
enum Haptics {
    static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
    static func impact() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
