import XCTest
import ReyForgeCore
@testable import ReyForge

/// Runs the built-in open-source model (llama.cpp) inside the Simulator.
/// CI passes the cached GGUF path through TEST_RUNNER_REYFORGE_MODEL_PATH.
final class OnDeviceAITests: XCTestCase {
    static var engine: LlamaEngine?

    func modelURL() throws -> URL {
        if let p = ProcessInfo.processInfo.environment["REYFORGE_MODEL_PATH"], FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        if let bundled = LocalModel.bundled.localURL { return bundled }
        throw XCTSkip("No GGUF model available to this test run")
    }

    func loadedEngine() throws -> LlamaEngine {
        if let e = Self.engine { return e }
        let e = LlamaEngine(modelURL: try modelURL(), displayName: "Qwen3.5 2B (test)")
        e.contextLength = 4096
        try e.load()
        Self.engine = e
        return e
    }

    func testGrammarConstrainedContentGeneration() async throws {
        let engine = try loadedEngine()
        let request = LLMRequest(system: Prompts.contentSystem,
                                 messages: [LLMMessage(role: "user", content: "Topic: beekeeping club. Give a title, subtitle and 3 short items.")],
                                 grammar: Grammars.content, maxTokens: 1200, temperature: 0.2)
        var streamed = ""
        let text = try await engine.generate(request, stream: LLMStream(onText: { streamed += $0 }))
        XCTAssertFalse(text.isEmpty)
        XCTAssertEqual(text, streamed)
        let json = Value.fromJSONString(Prompts.extractJSON(text))
        XCTAssertNotNil(json, "grammar output must be JSON: \(text)")
        print("Generated:", text, "stats:", engine.lastStats.tokensPerSecond, "tok/s")
    }

    func testAgentBuildsElementsWithTheLocalModel() async throws {
        let engine = try loadedEngine()
        let project = Templates.template("blank")!.makeProject(named: "Garden")
        let agent = VibeAgent(engine: engine)
        let result = await agent.respond(to: "Add a card with three watering tips for houseplants", project: project, context: EditorContext(screenID: project.screens.first?.id))
        let updated = try XCTUnwrap(result.project, result.reply)
        let before = project.allNodes.count
        XCTAssertGreaterThan(updated.allNodes.count, before, "the agent added elements")
        XCTAssertFalse(result.reply.isEmpty)
        XCTAssertTrue(ProjectValidator.errors(updated).isEmpty)
    }

    func testOfflineDesignEngineBuildsAFullApp() async {
        let project = Templates.template("blank")!.makeProject(named: "Habit")
        let result = await VibeAgent(engine: nil).respond(to: "Build a habit tracker app with a dashboard, habit list and settings", project: project)
        let p = result.project
        XCTAssertNotNil(p)
        XCTAssertGreaterThanOrEqual(p?.screens.count ?? 0, 3)
        XCTAssertFalse(result.suggestions.isEmpty)
    }
}
