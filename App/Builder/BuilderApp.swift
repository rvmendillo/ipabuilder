import SwiftUI
import ReyForgeCore
import Zsign

@main
struct ReyForgeBuilderApp: App {
    @StateObject private var store: RuntimeStore = {
        SymbolResolver.validator = { UIImage(systemName: $0) != nil }
        let project = Templates.all.first!.makeProject(named: "Preview")
        return RuntimeStore(project: project, mode: .run)
    }()

    var body: some Scene {
        WindowGroup {
            RuntimeRootView(store: store)
                .onAppear {
                    // Link checks for the signer and the on-device model engine.
                    _ = Zsign.checkSigned(appExecutable: Bundle.main.executablePath ?? "")
                    if let url = Bundle.main.url(forResource: "Qwen3.5-2B-Q4_K_M", withExtension: "gguf", subdirectory: "Models") {
                        _ = LlamaEngine(modelURL: url)
                    }
                }
        }
    }
}
