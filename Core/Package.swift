// swift-tools-version:5.9
import PackageDescription
import Foundation

// ReyForgeCore is the platform-independent heart of ReyForge: the project model,
// component registry, expression/logic engine, ReyForge Script (the AI layout
// language), the design engine, templates, IPA assembly and install helpers.
// It builds and tests on Linux and macOS, and is linked into the iOS apps.

var targets: [Target] = [
    .target(
        name: "ReyForgeCore",
        path: "Sources/ReyForgeCore"
    ),
    .testTarget(
        name: "ReyForgeCoreTests",
        dependencies: ["ReyForgeCore"],
        path: "Tests/ReyForgeCoreTests"
    ),
]

var products: [Product] = [
    .library(name: "ReyForgeCore", targets: ["ReyForgeCore"]),
]

// Optional on-device-model development target. Set REYFORGE_LLAMA_DIR to a
// directory containing include/llama.h (+ ggml headers) and lib/libllama.so to
// build and run the same LlamaEngine.swift used by the iOS app on Linux/macOS.
if let llamaDir = ProcessInfo.processInfo.environment["REYFORGE_LLAMA_DIR"], !llamaDir.isEmpty {
    targets += [
        .systemLibrary(name: "llama", path: "Sources/llama"),
        .target(
            name: "ReyForgeLlama",
            dependencies: ["ReyForgeCore", "llama"],
            path: "Sources/ReyForgeLlama",
            cSettings: [.unsafeFlags(["-I\(llamaDir)/include"])],
            swiftSettings: [.unsafeFlags(["-I\(llamaDir)/include", "-Xcc", "-I\(llamaDir)/include"])],
            linkerSettings: [.unsafeFlags(["-L\(llamaDir)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(llamaDir)/lib"])]
        ),
        .executableTarget(
            name: "rf-ai-eval",
            dependencies: ["ReyForgeCore", "ReyForgeLlama"],
            path: "Sources/rf-ai-eval",
            swiftSettings: [.unsafeFlags(["-Xcc", "-I\(llamaDir)/include"])],
            linkerSettings: [.unsafeFlags(["-L\(llamaDir)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(llamaDir)/lib"])]
        ),
    ]
}

let package = Package(
    name: "ReyForgeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: targets
)
