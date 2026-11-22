import Foundation

/// A platform-neutral rectangle (the canvas converts CGRect ⇄ RFRect).
public struct RFRect: Hashable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { max(0, width) * max(0, height) }
    public func contains(_ px: Double, _ py: Double) -> Bool { px >= minX && px <= maxX && py >= minY && py <= maxY }
    public func insetBy(_ dx: Double, _ dy: Double) -> RFRect { RFRect(x: x + dx, y: y + dy, width: max(0, width - 2 * dx), height: max(0, height - 2 * dy)) }
}

/// Where a dragged element (an existing node or a new one from the library) will be dropped.
public struct DropTarget: Hashable {
    public enum Placement: Hashable { case inside, before, after }
    public var containerID: String
    public var index: Int
    /// The node the drop is relative to (for highlighting); equals containerID for `.inside`.
    public var referenceID: String
    public var placement: Placement
    /// A thin rectangle showing the insertion point (or the container frame for `.inside` on empty containers).
    public var indicator: RFRect
    /// For free layouts (ZStack): the offset of the drop point inside the container.
    public var freeOffset: (x: Double, y: Double)?

    public static func == (a: DropTarget, b: DropTarget) -> Bool {
        a.containerID == b.containerID && a.index == b.index && a.referenceID == b.referenceID && a.placement == b.placement && a.indicator == b.indicator
            && a.freeOffset?.x == b.freeOffset?.x && a.freeOffset?.y == b.freeOffset?.y
    }
    public func hash(into h: inout Hasher) { h.combine(containerID); h.combine(index); h.combine(referenceID) }
}

/// Resolves drop targets from rendered node frames. Pure logic so it is unit-tested on every platform.
public enum DropPlanner {
    public enum Axis { case vertical, horizontal, reading, free }

    public static func axis(of node: Node) -> Axis {
        switch node.type {
        case .hstack: return .horizontal
        case .scroll: return node.string("axis") == "vertical" ? .vertical : .horizontal
        case .grid: return .reading
        case .zstack: return .free
        case .pager: return .horizontal
        default: return .vertical
        }
    }

    /// - Parameters:
    ///   - screen: the screen being edited.
    ///   - frames: rendered frames of nodes, all in one coordinate space.
    ///   - point: the drag location in the same space.
    ///   - dragging: the id of the node being moved (nil when inserting a new node).
    ///   - draggedType: component type of the dragged element.
    public static func target(in screen: Screen, frames: [String: RFRect], point: (x: Double, y: Double),
                              dragging: String?, draggedType: ComponentType) -> DropTarget? {
        // Collect candidates under the point (depth-first with parents).
        struct Entry { let node: Node; let parent: Node?; let index: Int; let depth: Int }
        var entries: [Entry] = []
        func walk(_ n: Node, parent: Node?, index: Int, depth: Int) {
            if let d = dragging, n.id == d { return } // skip the dragged subtree
            entries.append(Entry(node: n, parent: parent, index: index, depth: depth))
            for (i, c) in n.children.enumerated() { walk(c, parent: n, index: i, depth: depth + 1) }
        }
        walk(screen.root, parent: nil, index: 0, depth: 0)

        let hits = entries.filter { e in frames[e.node.id].map { $0.contains(point.x, point.y) } ?? false }
        let best = hits.max { a, b in
            if a.depth != b.depth { return a.depth < b.depth }
            return (frames[a.node.id]?.area ?? 0) > (frames[b.node.id]?.area ?? 0)
        }

        guard let hit = best else {
            // Outside every frame: append to the screen root (below or above the content).
            let root = screen.root
            let children = root.children.filter { $0.id != dragging }
            let rootFrame = frames[root.id]
            let atTop = rootFrame.map { point.y < $0.minY } ?? false
            return insertionInside(root, frames: frames, point: point, dragging: dragging, forcedIndex: atTop ? 0 : children.count, fallbackFrame: rootFrame)
        }

        let node = hit.node
        let spec = ComponentRegistry.spec(for: node.type)
        let frame = frames[node.id]!
        let isRoot = hit.parent == nil
        let accepts = isRoot || (spec.isContainer && ComponentRegistry.canContain(node.type, draggedType))

        if accepts {
            // Near the edge of a (non-root) container → before/after it; otherwise inside.
            let edgeX = min(14, frame.width * 0.2), edgeY = min(14, frame.height * 0.2)
            let inner = frame.insetBy(edgeX, edgeY)
            if isRoot || inner.contains(point.x, point.y) {
                if axis(of: node) == .free {
                    let count = node.children.filter { $0.id != dragging }.count
                    var t = DropTarget(containerID: node.id, index: count, referenceID: node.id, placement: .inside, indicator: frame, freeOffset: nil)
                    t.freeOffset = (max(0, point.x - frame.minX), max(0, point.y - frame.minY))
                    return t
                }
                return insertionInside(node, frames: frames, point: point, dragging: dragging, forcedIndex: nil, fallbackFrame: frame)
            }
        }

        // Before / after the hit node within its parent.
        guard let parent = hit.parent else { return nil }
        let siblings = parent.children.filter { $0.id != dragging }
        let idx = siblings.firstIndex { $0.id == node.id } ?? hit.index
        let ax = axis(of: parent)
        let after: Bool
        switch ax {
        case .horizontal, .reading: after = point.x > frame.midX
        case .vertical, .free: after = point.y > frame.midY
        }
        let indicator: RFRect
        switch ax {
        case .horizontal, .reading:
            indicator = RFRect(x: (after ? frame.maxX : frame.minX) - 1.5, y: frame.minY, width: 3, height: frame.height)
        case .vertical, .free:
            indicator = RFRect(x: frame.minX, y: (after ? frame.maxY : frame.minY) - 1.5, width: frame.width, height: 3)
        }
        // Convert the index among the remaining siblings back to an index in the original child list.
        let originalIndex = originalChildIndex(parent: parent, filteredIndex: idx + (after ? 1 : 0), dragging: dragging)
        return DropTarget(containerID: parent.id, index: originalIndex, referenceID: node.id, placement: after ? .after : .before, indicator: indicator, freeOffset: nil)
    }

    /// Index inside a container computed from its children's frames.
    static func insertionInside(_ container: Node, frames: [String: RFRect], point: (x: Double, y: Double), dragging: String?,
                                forcedIndex: Int?, fallbackFrame: RFRect?) -> DropTarget {
        let children = container.children.filter { $0.id != dragging }
        let ax = axis(of: container)
        var index = children.count
        if let f = forcedIndex {
            index = f
        } else {
            for (i, c) in children.enumerated() {
                guard let cf = frames[c.id] else { continue }
                let before: Bool
                switch ax {
                case .horizontal: before = point.x < cf.midX
                case .reading: before = point.y < cf.minY || (point.y <= cf.maxY && point.x < cf.midX)
                case .vertical, .free: before = point.y < cf.midY
                }
                if before { index = i; break }
            }
        }
        // Indicator: a line at the insertion point, or the container frame when it is empty.
        var indicator = fallbackFrame ?? RFRect(x: point.x - 40, y: point.y - 1.5, width: 80, height: 3)
        let frameOf = { (i: Int) -> RFRect? in children.indices.contains(i) ? frames[children[i].id] : nil }
        let horizontal = ax == .horizontal || ax == .reading
        if let next = frameOf(index) {
            indicator = horizontal ? RFRect(x: next.minX - 1.5, y: next.minY, width: 3, height: next.height)
                                   : RFRect(x: next.minX, y: next.minY - 1.5, width: next.width, height: 3)
        } else if let prev = frameOf(index - 1) {
            indicator = horizontal ? RFRect(x: prev.maxX - 1.5, y: prev.minY, width: 3, height: prev.height)
                                   : RFRect(x: prev.minX, y: prev.maxY - 1.5, width: prev.width, height: 3)
        }
        let original = originalChildIndex(parent: container, filteredIndex: index, dragging: dragging)
        return DropTarget(containerID: container.id, index: original, referenceID: container.id, placement: .inside, indicator: indicator, freeOffset: nil)
    }

    /// The dragged node is excluded while computing; `Project.move` expects an index in the original list.
    static func originalChildIndex(parent: Node, filteredIndex: Int, dragging: String?) -> Int {
        guard let d = dragging, let draggedIndex = parent.children.firstIndex(where: { $0.id == d }) else { return filteredIndex }
        return filteredIndex >= draggedIndex ? filteredIndex + 1 : filteredIndex
    }
}

public extension Project {
    /// Applies a drop of an existing node. Returns true when something changed.
    @discardableResult
    mutating func applyDrop(moving nodeID: String, to target: DropTarget) -> Bool {
        guard let current = locate(nodeID) else { return false }
        let currentParent = parent(of: nodeID)?.id
        if let off = target.freeOffset {
            if currentParent == target.containerID {
                return updateNode(nodeID) { $0.style.offsetX = off.x.rounded(); $0.style.offsetY = off.y.rounded() }
            }
            guard move(nodeID, to: target.containerID, at: target.index) else { return false }
            return updateNode(nodeID) { $0.style.offsetX = off.x.rounded(); $0.style.offsetY = off.y.rounded() }
        }
        if currentParent == target.containerID, let idx = current.path.last, target.index == idx || target.index == idx + 1 { return false }
        let ok = move(nodeID, to: target.containerID, at: target.index)
        if ok, node(id: target.containerID)?.type != .zstack {
            // Leaving a free layout: offsets no longer make sense.
            updateNode(nodeID) { $0.style.offsetX = nil; $0.style.offsetY = nil }
        }
        return ok
    }

    /// Inserts a new node at a drop target. Returns the inserted node id.
    @discardableResult
    mutating func applyDrop(inserting node: Node, to target: DropTarget) -> String? {
        var n = node
        if let off = target.freeOffset { n.style.offsetX = off.x.rounded(); n.style.offsetY = off.y.rounded() }
        return insert(n, into: target.containerID, at: target.index) ? n.id : nil
    }
}
