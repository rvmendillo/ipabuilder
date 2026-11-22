import Foundation

public struct NodeLocation: Hashable {
    public var screenIndex: Int
    /// Child indices from the screen root. Empty path = the root container itself.
    public var path: [Int]
    public var isRoot: Bool { path.isEmpty }
    public var parentPath: [Int]? { path.isEmpty ? nil : Array(path.dropLast()) }
}

extension Node {
    func node(at path: ArraySlice<Int>) -> Node? {
        guard let first = path.first else { return self }
        guard children.indices.contains(first) else { return nil }
        return children[first].node(at: path.dropFirst())
    }

    mutating func modify(at path: ArraySlice<Int>, _ f: (inout Node) -> Void) -> Bool {
        guard let first = path.first else { f(&self); return true }
        guard children.indices.contains(first) else { return false }
        return children[first].modify(at: path.dropFirst(), f)
    }

    func path(to id: String) -> [Int]? {
        if self.id == id { return [] }
        for (i, c) in children.enumerated() {
            if let p = c.path(to: id) { return [i] + p }
        }
        return nil
    }

    public func contains(id: String) -> Bool { path(to: id) != nil }
}

public extension Project {
    // MARK: Screens

    func screenIndex(id: String) -> Int? { screens.firstIndex { $0.id == id } }

    func screen(id: String) -> Screen? { screens.first { $0.id == id } }

    /// Finds a screen by id or (fuzzy, case-insensitive) name.
    func screen(named raw: String) -> Screen? {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return nil }
        if let s = screens.first(where: { $0.id.lowercased() == q }) { return s }
        if let s = screens.first(where: { $0.name.lowercased() == q || $0.title.lowercased() == q }) { return s }
        let squashed = q.replacingOccurrences(of: " ", with: "")
        if let s = screens.first(where: { $0.name.lowercased().replacingOccurrences(of: " ", with: "") == squashed }) { return s }
        if let s = screens.first(where: { $0.name.lowercased().hasPrefix(q) || q.hasPrefix($0.name.lowercased()) }) { return s }
        let singular = q.hasSuffix("s") ? String(q.dropLast()) : q + "s"
        return screens.first { $0.name.lowercased() == singular }
    }

    func screenName(_ id: String) -> String { screen(id: id)?.name ?? id }

    var initialScreen: Screen? {
        if let id = navigation.initialScreenID, let s = screen(id: id) { return s }
        return screens.first
    }

    @discardableResult
    mutating func addScreen(_ screen: Screen, asTab: Bool = false) -> String {
        screens.append(screen)
        if asTab { setTab(screen.id, enabled: true) }
        if navigation.initialScreenID == nil { navigation.initialScreenID = screen.id }
        return screen.id
    }

    mutating func removeScreen(id: String) {
        screens.removeAll { $0.id == id }
        navigation.tabs.removeAll { $0.screenID == id }
        if navigation.initialScreenID == id { navigation.initialScreenID = navigation.tabs.first?.screenID ?? screens.first?.id }
        if navigation.tabs.isEmpty { navigation.style = .stack }
    }

    @discardableResult
    mutating func duplicateScreen(id: String) -> String? {
        guard let i = screenIndex(id: id) else { return nil }
        var copy = screens[i]
        copy.id = IDGen.short("s")
        copy.name = uniqueScreenName(copy.name + " Copy")
        copy.title = copy.name
        copy.root = copy.root.clonedWithNewIDs()
        screens.insert(copy, at: i + 1)
        return copy.id
    }

    func uniqueScreenName(_ base: String) -> String {
        var name = base
        var n = 2
        while screens.contains(where: { $0.name.lowercased() == name.lowercased() }) { name = "\(base) \(n)"; n += 1 }
        return name
    }

    mutating func setTab(_ screenID: String, enabled: Bool) {
        guard let s = screen(id: screenID) else { return }
        if enabled {
            if !navigation.tabs.contains(where: { $0.screenID == screenID }) {
                navigation.tabs.append(TabItem(screenID: screenID, title: s.name, icon: s.icon))
            }
            if navigation.tabs.count >= 1 { navigation.style = .tabs }
            if navigation.tabs.count == 1 { navigation.initialScreenID = screenID }
        } else {
            navigation.tabs.removeAll { $0.screenID == screenID }
            if navigation.tabs.isEmpty { navigation.style = .stack }
        }
    }

    func isTab(_ screenID: String) -> Bool { navigation.tabs.contains { $0.screenID == screenID } }

    // MARK: Node lookup

    func locate(_ nodeID: String) -> NodeLocation? {
        for (i, s) in screens.enumerated() {
            if let p = s.root.path(to: nodeID) { return NodeLocation(screenIndex: i, path: p) }
        }
        return nil
    }

    func node(id: String) -> Node? {
        guard let loc = locate(id) else { return nil }
        return screens[loc.screenIndex].root.node(at: loc.path[...])
    }

    func node(at loc: NodeLocation) -> Node? {
        guard screens.indices.contains(loc.screenIndex) else { return nil }
        return screens[loc.screenIndex].root.node(at: loc.path[...])
    }

    func parent(of nodeID: String) -> Node? {
        guard let loc = locate(nodeID), let pp = loc.parentPath else { return nil }
        return screens[loc.screenIndex].root.node(at: pp[...])
    }

    func screenContaining(nodeID: String) -> Screen? {
        guard let loc = locate(nodeID) else { return nil }
        return screens[loc.screenIndex]
    }

    /// All nodes with their screen, depth-first.
    var allNodes: [(screen: Screen, node: Node)] {
        screens.flatMap { s in s.root.flattened.map { (s, $0) } }
    }

    // MARK: Mutation

    @discardableResult
    mutating func updateNode(_ nodeID: String, _ f: (inout Node) -> Void) -> Bool {
        guard let loc = locate(nodeID) else { return false }
        return screens[loc.screenIndex].root.modify(at: loc.path[...], f)
    }

    @discardableResult
    mutating func removeNode(_ nodeID: String) -> Node? {
        guard let loc = locate(nodeID), let pp = loc.parentPath, let idx = loc.path.last else { return nil }
        var removed: Node?
        _ = screens[loc.screenIndex].root.modify(at: pp[...]) { parent in
            if parent.children.indices.contains(idx) { removed = parent.children.remove(at: idx) }
        }
        return removed
    }

    /// Inserts a node into a container (or the screen root). Returns false if the container can't accept it.
    @discardableResult
    mutating func insert(_ node: Node, into containerID: String, at index: Int? = nil) -> Bool {
        guard let loc = locate(containerID), let container = self.node(at: loc) else { return false }
        guard ComponentRegistry.canContain(container.type, node.type) || loc.isRoot else { return false }
        return screens[loc.screenIndex].root.modify(at: loc.path[...]) { parent in
            let i = min(max(0, index ?? parent.children.count), parent.children.count)
            parent.children.insert(node, at: i)
        }
    }

    @discardableResult
    mutating func append(_ node: Node, toScreen screenID: String) -> Bool {
        guard let i = screenIndex(id: screenID) else { return false }
        screens[i].root.children.append(node)
        return true
    }

    /// Inserts a node after a sibling (keeps the same container).
    @discardableResult
    mutating func insert(_ node: Node, after siblingID: String) -> Bool {
        guard let loc = locate(siblingID), let pp = loc.parentPath, let idx = loc.path.last else { return false }
        return screens[loc.screenIndex].root.modify(at: pp[...]) { parent in
            parent.children.insert(node, at: min(idx + 1, parent.children.count))
        }
    }

    /// Moves a node to a new container and index. Refuses to move a node into itself or its descendants.
    @discardableResult
    mutating func move(_ nodeID: String, to containerID: String, at index: Int) -> Bool {
        guard nodeID != containerID, let moving = node(id: nodeID), !moving.contains(id: containerID) else { return false }
        guard let target = node(id: containerID), ComponentRegistry.canContain(target.type, moving.type) || locate(containerID)?.isRoot == true else { return false }
        guard let src = locate(nodeID), let srcParent = src.parentPath, let srcIndex = src.path.last else { return false }
        let sameParent = parent(of: nodeID)?.id == containerID
        guard let removed = removeNode(nodeID) else { return false }
        var dest = index
        if sameParent, srcIndex < index { dest -= 1 }
        if !insert(removed, into: containerID, at: dest) {
            // Roll back.
            _ = screens[src.screenIndex].root.modify(at: srcParent[...]) { $0.children.insert(removed, at: min(srcIndex, $0.children.count)) }
            return false
        }
        return true
    }

    @discardableResult
    mutating func moveWithinParent(_ nodeID: String, by delta: Int) -> Bool {
        guard let loc = locate(nodeID), let pp = loc.parentPath, let idx = loc.path.last else { return false }
        var ok = false
        _ = screens[loc.screenIndex].root.modify(at: pp[...]) { parent in
            let target = idx + delta
            guard parent.children.indices.contains(target) else { return }
            parent.children.swapAt(idx, target)
            ok = true
        }
        return ok
    }

    @discardableResult
    mutating func duplicateNode(_ nodeID: String) -> String? {
        guard let original = node(id: nodeID), locate(nodeID)?.isRoot == false else { return nil }
        var copy = original.clonedWithNewIDs()
        if let ox = copy.style.offsetX, let oy = copy.style.offsetY, parent(of: nodeID)?.type == .zstack {
            copy.style.offsetX = ox + 16; copy.style.offsetY = oy + 16
        }
        return insert(copy, after: nodeID) ? copy.id : nil
    }

    /// Wraps a node in a new container (VStack, HStack, Card…). Returns the container id.
    @discardableResult
    mutating func wrap(_ nodeID: String, in type: ComponentType) -> String? {
        guard ComponentRegistry.spec(for: type).isContainer, let original = node(id: nodeID), let loc = locate(nodeID), !loc.isRoot else { return nil }
        var container = Node(type: type, props: ComponentRegistry.spec(for: type).defaultProps, style: ComponentRegistry.spec(for: type).defaultStyle)
        container.children = [original]
        guard let pp = loc.parentPath, let idx = loc.path.last else { return nil }
        _ = screens[loc.screenIndex].root.modify(at: pp[...]) { parent in parent.children[idx] = container }
        return container.id
    }

    /// Replaces a container with its children.
    @discardableResult
    mutating func unwrap(_ containerID: String) -> Bool {
        guard let loc = locate(containerID), let pp = loc.parentPath, let idx = loc.path.last, let container = node(id: containerID), !container.children.isEmpty else { return false }
        return screens[loc.screenIndex].root.modify(at: pp[...]) { parent in
            parent.children.remove(at: idx)
            parent.children.insert(contentsOf: container.children, at: idx)
        }
    }

    // MARK: Variables

    func variable(named name: String) -> Variable? {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        return variables.first { $0.name.lowercased() == q }
    }

    /// Returns the existing variable or creates one. The returned name is the canonical one.
    @discardableResult
    mutating func ensureVariable(_ rawName: String, type: ValueKind, initial: Value? = nil, persist: Bool = false) -> String {
        let name = Variable.sanitize(rawName)
        if let v = variable(named: name) { return v.name }
        variables.append(Variable(name: name, type: type, initial: initial, persist: persist))
        return name
    }

    mutating func renameVariable(_ old: String, to new: String) {
        let newName = Variable.sanitize(new)
        guard let i = variables.firstIndex(where: { $0.name == old }), variable(named: newName) == nil else { return }
        variables[i].name = newName
        func fix(_ s: String) -> String {
            // Replace whole-word occurrences only.
            var out = ""
            var word = ""
            func flush() { out += (word == old ? newName : word); word = "" }
            for ch in s {
                if ch.isLetter || ch.isNumber || ch == "_" || ch == "$" { word.append(ch) } else { flush(); out.append(ch) }
            }
            flush()
            return out
        }
        func fixActions(_ actions: inout [Action]) {
            for j in actions.indices {
                for (k, v) in actions[j].params { if case .string(let s) = v { actions[j].params[k] = .string(fix(s)) } }
                fixActions(&actions[j].then)
                fixActions(&actions[j].otherwise)
            }
        }
        func fixNode(_ n: inout Node) {
            if n.binding == old { n.binding = newName }
            if let r = n.repeatSource { n.repeatSource = fix(r) }
            if let v = n.visibleIf { n.visibleIf = fix(v) }
            for (k, v) in n.props { if case .string(let s) = v, s.contains(old) { n.props[k] = .string(fix(s)) } }
            for e in n.events.indices { fixActions(&n.events[e].actions) }
            for c in n.children.indices { fixNode(&n.children[c]) }
        }
        for s in screens.indices {
            fixNode(&screens[s].root)
            fixActions(&screens[s].onAppear)
            screens[s].title = fix(screens[s].title)
        }
    }

    /// Names of variables the user can bind to a component of the given kind.
    func variableNames(of kind: ValueKind? = nil) -> [String] {
        variables.filter { kind == nil || $0.type == kind }.map { $0.name }
    }

    mutating func touch() { updatedAt = Date() }
}

// MARK: - Validation

public struct ProjectIssue: Hashable, CustomStringConvertible {
    public enum Severity: String { case error, warning }
    public let severity: Severity
    public let message: String
    public let nodeID: String?
    public let screenID: String?
    public var description: String { "[\(severity.rawValue)] \(message)" }
}

public enum ProjectValidator {
    public static func validate(_ project: Project) -> [ProjectIssue] {
        var issues: [ProjectIssue] = []
        if project.screens.isEmpty {
            issues.append(ProjectIssue(severity: .error, message: "The app has no screens.", nodeID: nil, screenID: nil))
        }
        if !BundleID.isValid(project.bundleID) {
            issues.append(ProjectIssue(severity: .error, message: "Bundle identifier “\(project.bundleID)” is not valid (use reverse DNS like com.you.app).", nodeID: nil, screenID: nil))
        }
        if project.brand.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ProjectIssue(severity: .error, message: "App display name is empty.", nodeID: nil, screenID: nil))
        }
        let screenIDs = Set(project.screens.map { $0.id })
        let varNames = Set(project.variables.map { $0.name })
        var ids = Set<String>()

        func checkActions(_ actions: [Action], screen: Screen, nodeID: String?) {
            for a in actions {
                switch a.kind {
                case .navigate, .switchTab:
                    let target = a.string("screen")
                    if !screenIDs.contains(target) && project.screen(named: target) == nil {
                        issues.append(ProjectIssue(severity: .error, message: "\(ActionRegistry.describe(a)) points to a missing screen.", nodeID: nodeID, screenID: screen.id))
                    }
                case .setVariable, .toggleVariable, .increment, .decrement, .appendItem, .removeItem, .clearList, .updateItem:
                    let v = a.string("variable")
                    if !varNames.contains(v) {
                        issues.append(ProjectIssue(severity: .warning, message: "Action uses unknown variable “\(v)”.", nodeID: nodeID, screenID: screen.id))
                    }
                case .condition, .validate:
                    if let err = ExpressionEngine.validate(a.string("condition")) {
                        issues.append(ProjectIssue(severity: .warning, message: "Condition “\(a.string("condition"))”: \(err)", nodeID: nodeID, screenID: screen.id))
                    }
                default: break
                }
                checkActions(a.then, screen: screen, nodeID: nodeID)
                checkActions(a.otherwise, screen: screen, nodeID: nodeID)
            }
        }

        for s in project.screens {
            checkActions(s.onAppear, screen: s, nodeID: nil)
            for n in s.root.flattened {
                if ids.contains(n.id) {
                    issues.append(ProjectIssue(severity: .error, message: "Duplicate component id \(n.id).", nodeID: n.id, screenID: s.id))
                }
                ids.insert(n.id)
                if let b = n.binding, !b.isEmpty, !varNames.contains(b) {
                    issues.append(ProjectIssue(severity: .warning, message: "\(n.displayName) is bound to unknown variable “\(b)”.", nodeID: n.id, screenID: s.id))
                }
                if n.type == .navLink {
                    let dest = n.string("destination")
                    if !dest.isEmpty && !screenIDs.contains(dest) && project.screen(named: dest) == nil {
                        issues.append(ProjectIssue(severity: .warning, message: "\(n.displayName) links to a missing screen.", nodeID: n.id, screenID: s.id))
                    }
                }
                if !n.children.isEmpty && !ComponentRegistry.spec(for: n.type).isContainer {
                    issues.append(ProjectIssue(severity: .warning, message: "\(n.displayName) cannot contain children.", nodeID: n.id, screenID: s.id))
                }
                for e in n.events { checkActions(e.actions, screen: s, nodeID: n.id) }
            }
        }
        return issues
    }

    public static func errors(_ project: Project) -> [ProjectIssue] { validate(project).filter { $0.severity == .error } }
}
