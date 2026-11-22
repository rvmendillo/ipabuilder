import SwiftUI
import ReyForgeCore

@main
struct ReyForgeBuilderApp: App {
    @StateObject private var library = ProjectLibrary()

    init() {
        SymbolResolver.validator = { UIImage(systemName: $0) != nil }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(library)
                .tint(RF.violet)
                .onOpenURL { url in library.handleOpen(url) }
        }
    }
}
