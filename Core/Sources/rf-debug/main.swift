import ReyForgeCore
import Foundation
let msg = CommandLine.arguments.dropFirst().joined(separator: " ")
let i = RequestAnalyzer.analyze(msg)
print("op=\(i.operation) archetypes=\(i.archetypes) domain=\(String(describing: i.domain)) topic=\(String(describing: i.topic)) comps=\(i.components.map { "\($0.type):\($0.label ?? "-")" })")
let sem = DispatchSemaphore(value: 0)
Task {
    let r = await VibeAgent().respond(to: msg, project: Project(name: "Untitled"))
    print(r.script)
    print("---- screens:", r.project?.screens.map { $0.name } ?? [])
    print("---- reply:\n\(r.reply)\n\(r.highlights.joined(separator: "\n"))")
    sem.signal()
}
sem.wait()
