import SwiftUI
import ReyForgeCore
import UserNotifications

/// How a project is being rendered.
enum RenderMode: Equatable {
    /// Builder canvas: elements are selectable, not interactive.
    case design
    /// Preview or generated app: fully interactive.
    case run
}

struct Presentation: Identifiable, Equatable {
    let id = UUID()
    let screenID: String
    let fullScreen: Bool
}

struct AlertRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let buttons: [String]
    let destructiveIndex: Int?
    let resume: (Int) -> Void
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: String
}

/// Live state of a running ReyForge project (variables, navigation, presentation, feedback).
@MainActor
final class RuntimeStore: ObservableObject, RuntimeHost {
    @Published private(set) var project: Project
    @Published var selectedTab: String = ""
    @Published var paths: [String: [String]] = [:]
    @Published var rootScreenID: String = ""
    @Published var sheet: Presentation?
    @Published var cover: Presentation?
    @Published var alert: AlertRequest?
    @Published var toast: Toast?
    @Published var shareItem: ShareItem?
    @Published var splashFinished = false
    @Published private(set) var revision = 0
    let mode: RenderMode
    let state: StateStore
    private(set) var runner: ActionRunner!
    /// Where imported images live (builder project folder or the app bundle).
    var assetsDirectory: URL?
    var onLog: ((String) -> Void)?
    var openURLHandler: ((URL) -> Void)?

    struct ShareItem: Identifiable { let id = UUID(); let text: String }

    init(project: Project, mode: RenderMode, persistence: PersistenceBackend? = nil, assetsDirectory: URL? = nil) {
        self.project = project
        self.mode = mode
        self.assetsDirectory = assetsDirectory
        state = StateStore(variables: project.variables, persistence: persistence ?? (mode == .run ? UserDefaultsPersistence(prefix: "rf.\(project.id.uuidString).") : MemoryPersistence()))
        runner = ActionRunner(project: project, state: state, http: URLSessionHTTPClient(), host: self)
        runner.onLog = { [weak self] line in self?.onLog?(line) }
        state.onChange = { [weak self] _ in
            guard let self else { return }
            self.revision &+= 1
        }
        resetNavigation()
    }

    /// Updates the project while keeping state (used by the live builder canvas).
    func update(project newValue: Project) {
        project = newValue
        state.configure(newValue.variables)
        runner.project = newValue
        if project.screen(id: rootScreenID) == nil || !(project.navigation.tabs.contains { $0.screenID == selectedTab } || project.navigation.tabs.isEmpty) {
            resetNavigation()
        }
        revision &+= 1
    }

    func resetNavigation() {
        let initial = project.initialScreen?.id ?? ""
        rootScreenID = initial
        selectedTab = project.navigation.tabs.first(where: { $0.screenID == initial })?.screenID ?? project.navigation.tabs.first?.screenID ?? initial
        paths = [:]
        sheet = nil
        cover = nil
    }

    var usesTabs: Bool {
        project.navigation.style == .tabs && project.navigation.tabs.count >= 2 && project.isTab(rootScreenID)
    }

    // MARK: Values

    func scope(_ locals: [String: Value] = [:]) -> Scope { Scope(locals: locals, globals: state) }

    func resolve(_ value: Value?, scope: Scope) -> Value {
        guard let v = value else { return .null }
        return Template.resolve(v, scope: scope)
    }

    func string(_ node: Node, _ key: String, _ scope: Scope) -> String { resolve(node.prop(key), scope: scope).stringValue }
    func number(_ node: Node, _ key: String, _ scope: Scope) -> Double? { resolve(node.prop(key), scope: scope).numberValue }
    func bool(_ node: Node, _ key: String, _ scope: Scope) -> Bool { resolve(node.prop(key), scope: scope).boolValue }

    func isVisible(_ node: Node, scope: Scope) -> Bool {
        guard let cond = node.visibleIf, !cond.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        return ValueResolver.condition(cond, scope: scope)
    }

    func items(for node: Node, scope: Scope) -> [Value]? {
        guard let src = node.repeatSource?.trimmingCharacters(in: .whitespaces), !src.isEmpty else { return nil }
        let v = Template.containsTemplate(src) ? Template.resolve(src, scope: scope) : ExpressionEngine.evaluate(src, scope: scope)
        if case .array(let a) = v { return a }
        if case .string(let s) = v, s == src { return state.value(src).arrayValue }
        return v.arrayValue
    }

    // MARK: Bindings

    private func ensure(_ name: String, _ kind: ValueKind, _ initial: Value?) {
        if state.definitions[name] == nil { state.ensure(name, kind: kind, initial: initial) }
    }

    func boolBinding(_ name: String?, initial: Bool, node: Node, scope: Scope) -> Binding<Bool> {
        guard let name = name, !name.isEmpty else { return .constant(initial) }
        ensure(name, .bool, .bool(initial))
        return Binding(get: { self.state.value(name).boolValue }, set: { v in
            guard self.mode == .run else { return }
            self.state.set(name, .bool(v))
            self.fire(.change, node: node, scope: scope.with("value", .bool(v)))
        })
    }

    func numberBinding(_ name: String?, initial: Double, node: Node, scope: Scope) -> Binding<Double> {
        guard let name = name, !name.isEmpty else { return .constant(initial) }
        ensure(name, .number, .number(initial))
        return Binding(get: { self.state.value(name).numberValue ?? initial }, set: { v in
            guard self.mode == .run else { return }
            self.state.set(name, .number(v))
            self.fire(.change, node: node, scope: scope.with("value", .number(v)))
        })
    }

    func stringBinding(_ name: String?, initial: String, node: Node, scope: Scope) -> Binding<String> {
        guard let name = name, !name.isEmpty else { return .constant(initial) }
        ensure(name, .text, .string(initial))
        return Binding(get: { self.state.value(name).stringValue }, set: { v in
            guard self.mode == .run else { return }
            self.state.set(name, .string(v))
            self.fire(.change, node: node, scope: scope.with("value", .string(v)))
        })
    }

    func dateBinding(_ name: String?, node: Node, scope: Scope) -> Binding<Date> {
        guard let name = name, !name.isEmpty else { return .constant(Date()) }
        ensure(name, .date, nil)
        return Binding(get: { self.state.value(name).date ?? Date() }, set: { v in
            guard self.mode == .run else { return }
            let s = ExpressionEngine.isoFormatter.string(from: v)
            self.state.set(name, .string(s))
            self.fire(.change, node: node, scope: scope.with("value", .string(s)))
        })
    }

    func colorBinding(_ name: String?, node: Node, scope: Scope, palette: ThemePalette) -> Binding<Color> {
        guard let name = name, !name.isEmpty else { return .constant(palette.accent) }
        ensure(name, .color, .string(project.theme.accent))
        return Binding(get: { palette.color(self.state.value(name).stringValue, fallback: palette.accent) }, set: { v in
            guard self.mode == .run else { return }
            self.state.set(name, .string(v.hexString))
            self.fire(.change, node: node, scope: scope.with("value", .string(v.hexString)))
        })
    }

    func setValue(_ name: String?, _ value: Value) {
        guard mode == .run, let name = name, !name.isEmpty else { return }
        state.set(name, value)
    }

    // MARK: Events

    func fire(_ event: EventKind, node: Node, scope: Scope) {
        let actions = node.handlers(for: event)
        guard mode == .run, !actions.isEmpty else { return }
        run(actions, scope: scope)
    }

    func run(_ actions: [Action], scope: Scope? = nil) {
        guard mode == .run, !actions.isEmpty else { return }
        let s = scope ?? self.scope()
        Task { await runner.run(actions, scope: s) }
    }

    func runAndWait(_ actions: [Action], scope: Scope? = nil) async {
        guard mode == .run, !actions.isEmpty else { return }
        await runner.run(actions, scope: scope ?? self.scope())
    }

    // MARK: RuntimeHost

    var contextKey: String {
        if let c = cover { return "cover:\(c.id)" }
        if let s = sheet { return "sheet:\(s.id)" }
        return usesTabs ? "tab:\(selectedTab)" : "stack:\(rootScreenID)"
    }

    func path(for key: String) -> Binding<[String]> {
        Binding(get: { self.paths[key] ?? [] }, set: { self.paths[key] = $0 })
    }

    func navigate(to screenID: String, style: String) {
        switch style {
        case "sheet":
            if sheet == nil { sheet = Presentation(screenID: screenID, fullScreen: false) }
            else { paths[contextKey, default: []].append(screenID) }
        case "fullScreen", "cover":
            cover = Presentation(screenID: screenID, fullScreen: true)
        case "replace", "root":
            sheet = nil; cover = nil
            paths = [:]
            if project.isTab(screenID) && project.navigation.style == .tabs {
                rootScreenID = screenID
                selectedTab = screenID
            } else {
                rootScreenID = screenID
            }
        default:
            if project.isTab(screenID) && usesTabs && sheet == nil && cover == nil {
                selectedTab = screenID
            } else {
                paths[contextKey, default: []].append(screenID)
            }
        }
    }

    func goBack() {
        let key = contextKey
        if var p = paths[key], !p.isEmpty { p.removeLast(); paths[key] = p; return }
        if cover != nil { cover = nil; return }
        if sheet != nil { sheet = nil; return }
    }

    func switchTab(to screenID: String) {
        sheet = nil; cover = nil
        if project.isTab(screenID) {
            if !project.isTab(rootScreenID) { rootScreenID = screenID }
            selectedTab = screenID
        } else {
            navigate(to: screenID, style: "push")
        }
    }

    func presentAlert(title: String, message: String, buttons: [String], destructiveIndex: Int?) async -> Int {
        await withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
            var resumed = false
            alert = AlertRequest(title: title, message: message, buttons: buttons, destructiveIndex: destructiveIndex) { index in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: index)
            }
        }
    }

    func showToast(_ message: String, style: String) {
        let t = Toast(message: message, style: style)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = t }
        Task {
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            if toast?.id == t.id { withAnimation(.easeOut(duration: 0.25)) { toast = nil } }
        }
    }

    func openURL(_ url: String) {
        let t = url.trimmingCharacters(in: .whitespaces)
        guard let u = URL(string: t.contains(":") ? t : "https://" + t) else { showToast("Invalid link", style: "error"); return }
        if let h = openURLHandler { h(u) } else { UIApplication.shared.open(u) }
    }

    func share(_ text: String) { shareItem = ShareItem(text: text) }

    func copy(_ text: String) { UIPasteboard.general.string = text }

    func haptic(_ style: String) {
        switch style {
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
        case "selection": UISelectionFeedbackGenerator().selectionChanged()
        case "heavy": UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func scheduleNotification(title: String, body: String, seconds: Double) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else {
                Task { @MainActor in self.showToast("Allow notifications in Settings to get reminders", style: "warning") }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
        }
    }

    // MARK: Images

    func image(forAsset id: String) -> UIImage? {
        guard let dir = assetsDirectory else { return nil }
        for ext in ["", ".png", ".jpg", ".jpeg", ".heic"] {
            let url = dir.appendingPathComponent(id + ext)
            if let img = UIImage(contentsOfFile: url.path) { return img }
        }
        return nil
    }

    /// Saves a picked photo and returns a value usable as an image source.
    func storePickedImage(_ data: Data) -> String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PickedImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString + ".jpg")
        if let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.85) { try? jpg.write(to: url) } else { try? data.write(to: url) }
        return url.absoluteString
    }
}
