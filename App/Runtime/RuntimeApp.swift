import SwiftUI
import ReyForgeCore

/// The precompiled player app. ReyForge copies it, embeds a project (ReyForgeProject.json),
/// rebrands it and signs it on-device to produce a real native IPA.
@main
struct ReyForgeRuntimeApp: App {
    @StateObject private var store = RuntimeLoader.makeStore()

    var body: some Scene {
        WindowGroup {
            RuntimeRootView(store: store)
                .onOpenURL { url in RuntimeLoader.handle(url, store: store) }
        }
    }
}

enum RuntimeLoader {
    @MainActor
    static func makeStore() -> RuntimeStore {
        SymbolResolver.validator = { UIImage(systemName: $0) != nil }
        let bundle = Bundle.main
        var project: Project
        if let url = bundle.url(forResource: "ReyForgeProject", withExtension: "json"), let data = try? Data(contentsOf: url), let p = try? Project.decode(data) {
            project = p
        } else {
            project = Templates.template("blank")!.makeProject(named: "ReyForge App")
        }
        let assets = bundle.url(forResource: AppAssembler.assetsFolder, withExtension: nil)
        return RuntimeStore(project: project, mode: .run, assetsDirectory: assets)
    }

    /// Deep links from the widget: <scheme>://screen/<id>
    @MainActor
    static func handle(_ url: URL, store: RuntimeStore) {
        guard url.host == "screen" else { return }
        let id = url.lastPathComponent
        if let s = store.project.screen(id: id) ?? store.project.screen(named: id) {
            store.splashFinished = true
            store.navigate(to: s.id, style: store.project.isTab(s.id) ? "push" : "push")
        }
    }
}
