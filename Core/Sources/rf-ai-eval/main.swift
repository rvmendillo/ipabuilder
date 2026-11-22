import Foundation
import ReyForgeCore
import ReyForgeLlama

// Usage: rf-ai-eval <model.gguf> ["prompt" ...]
// Runs ReyForge AI end-to-end with the on-device model and prints scripts, replies and timings.
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: rf-ai-eval model.gguf [prompts...]"); exit(1) }
let engine = LlamaEngine(modelURL: URL(fileURLWithPath: args[1]))
engine.gpuLayers = 0
let agent = VibeAgent(engine: engine)
let prompts = args.count > 2 ? Array(args.dropFirst(2)) : [
    "Create a dashboard for my beekeeping app",
    "show my top 3 goals with progress bars",
    "how do I make a button open another screen?",
    "add a card that explains our refund policy",
]

var project = Project(name: "Eval")
var home = Screen(name: "Home", icon: "house.fill")
home.root.children = [Node(type: .text, props: ["text": "Welcome"])]
project.addScreen(home)

let sem = DispatchSemaphore(value: 0)
Task {
    for p in prompts {
        let start = Date()
        var streamed = ""
        let r = await agent.respond(to: p, project: project, context: EditorContext(screenID: project.screens[0].id)) { e in
            switch e {
            case .scriptDelta(let t), .textDelta(let t): streamed += t
            default: break
            }
        }
        let s = engine.lastStats
        print("\n=== \(p)")
        print("op=\(r.intent.operation) engine=\(r.engineName) changes=\(r.changes.count) time=\(String(format: "%.1f", Date().timeIntervalSince(start)))s prompt=\(s.promptTokens)tok reused=\(s.reusedPrefix) gen=\(s.generatedTokens)tok \(String(format: "%.1f", s.tokensPerSecond))tok/s")
        if !streamed.isEmpty { print("--- model output:\n\(streamed.prefix(1400))") }
        print("--- reply:\n\(r.reply)")
        if !r.highlights.isEmpty { print(r.highlights.joined(separator: "\n")) }
        if let p2 = r.project { print("errors: \(ProjectValidator.errors(p2))") }
    }
    sem.signal()
}
sem.wait()
