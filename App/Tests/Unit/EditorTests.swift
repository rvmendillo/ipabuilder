import XCTest
import SwiftUI
import ReyForgeCore
@testable import ReyForge

@MainActor
final class EditorTests: XCTestCase {
    var library: ProjectLibrary!

    override func setUp() async throws {
        library = ProjectLibrary()
    }

    func makeEditor(_ template: String = "blank") -> EditorModel {
        let p = library.create(from: Templates.template(template), name: "Editor \(template) \(UUID().uuidString.prefix(4))")
        return EditorModel(project: p, library: library)
    }

    func testAddSelectUndoRedo() {
        let editor = makeEditor()
        let before = editor.currentScreen!.root.children.count
        let id = editor.addComponent(.button)
        XCTAssertNotNil(id)
        XCTAssertEqual(editor.selection, id)
        XCTAssertEqual(editor.currentScreen!.root.children.count, before + 1)
        editor.setProp(id!, "title", .string("Buy now"))
        XCTAssertEqual(editor.project.node(id: id!)?.string("title"), "Buy now")
        editor.undo()
        XCTAssertNotEqual(editor.project.node(id: id!)?.string("title"), "Buy now")
        editor.undo()
        XCTAssertNil(editor.project.node(id: id!))
        editor.redo()
        XCTAssertNotNil(editor.project.node(id: id!))
    }

    func testTypingCoalescesIntoOneUndoStep() {
        let editor = makeEditor()
        let id = editor.addComponent(.text)!
        for s in ["H", "He", "Hel", "Hell", "Hello"] { editor.setProp(id, "text", .string(s)) }
        XCTAssertEqual(editor.project.node(id: id)?.string("text"), "Hello")
        editor.undo()
        XCTAssertNotEqual(editor.project.node(id: id)?.string("text"), "Hell", "one undo reverts the whole typing burst")
    }

    func testDragToMoveUsesReportedFrames() {
        let editor = makeEditor()
        let a = editor.addComponent(.text)!
        editor.selection = nil
        let b = editor.addComponent(.button)!
        let root = editor.currentScreen!.root
        // Simulate rendered frames (global coordinates).
        editor.reportFrame(root.id, CGRect(x: 0, y: 100, width: 390, height: 700))
        for (i, child) in root.children.enumerated() {
            editor.reportFrame(child.id, CGRect(x: 16, y: 116 + CGFloat(i) * 60, width: 358, height: 44))
        }
        editor.canvasFrame = CGRect(x: 0, y: 100, width: 390, height: 700)
        // Drag `b` above the first child.
        let firstFrame = CGRect(x: 16, y: 116, width: 358, height: 44)
        editor.moveChanged(b, location: CGPoint(x: 100, y: firstFrame.minY + 5), translation: CGSize(width: 0, height: -200), freeLayout: false)
        XCTAssertNotNil(editor.dropIndicator)
        editor.moveEnded(b, location: CGPoint(x: 100, y: firstFrame.minY + 5), translation: CGSize(width: 0, height: -200), freeLayout: false)
        XCTAssertEqual(editor.currentScreen!.root.children.first?.id, b)
        XCTAssertTrue(editor.currentScreen!.root.children.contains { $0.id == a })
        XCTAssertNil(editor.dropIndicator)
    }

    func testLibraryDropInsertsAtLocation() {
        let editor = makeEditor()
        let root = editor.currentScreen!.root
        editor.reportFrame(root.id, CGRect(x: 0, y: 0, width: 390, height: 800))
        for (i, child) in root.children.enumerated() { editor.reportFrame(child.id, CGRect(x: 16, y: 16 + CGFloat(i) * 60, width: 358, height: 44)) }
        editor.canvasFrame = CGRect(x: 0, y: 0, width: 390, height: 800)
        editor.libraryDragEnded(.toggle, location: CGPoint(x: 100, y: 20))
        XCTAssertEqual(editor.currentScreen!.root.children.first?.type, .toggle)
        // Dropping outside the canvas does nothing.
        let count = editor.currentScreen!.root.children.count
        editor.libraryDragEnded(.slider, location: CGPoint(x: 100, y: 2000))
        XCTAssertEqual(editor.currentScreen!.root.children.count, count)
    }

    func testResizeAndFreeLayoutMove() {
        let editor = makeEditor()
        let z = editor.addComponent(.zstack)!
        let child = editor.project.node(id: z)!.children[0].id
        editor.resizeEnded(child, size: CGSize(width: 123, height: 61))
        XCTAssertEqual(editor.project.node(id: child)?.style.width, .fixed(124))
        XCTAssertEqual(editor.project.node(id: child)?.style.height, .fixed(60))
        editor.reportFrame(z, CGRect(x: 0, y: 0, width: 390, height: 300))
        let oldX = editor.project.node(id: child)?.style.offsetX ?? 0
        editor.moveEnded(child, location: CGPoint(x: 150, y: 150), translation: CGSize(width: 40, height: 20), freeLayout: true)
        XCTAssertEqual(editor.project.node(id: child)?.style.offsetX, oldX + 40)
    }

    func testContextMenuAndQuickEdit() {
        let editor = makeEditor()
        let id = editor.addComponent(.text)!
        let actions = editor.contextActions(for: id)
        XCTAssertTrue(actions.contains { $0.title == "Edit Text" })
        actions.first { $0.title == "Edit Text" }?.run()
        XCTAssertNotNil(editor.quickEdit)
        var e = editor.quickEdit!
        e.text = "Changed inline"
        editor.commitQuickEdit(e)
        XCTAssertEqual(editor.project.node(id: id)?.string("text"), "Changed inline")
        actions.first { $0.title == "Delete" }?.run()
        XCTAssertNil(editor.project.node(id: id))
    }

    func testScriptConsoleAndSave() async throws {
        let editor = makeEditor()
        let r = editor.runScript("SCREEN \"Extra\"\n  HEADING \"Hello from script\"\n  TOGGLE \"Alerts\" bind=alertsOn")
        XCTAssertFalse(r.changes.isEmpty)
        XCTAssertNotNil(editor.project.screen(named: "Extra"))
        XCTAssertNotNil(editor.project.variable(named: "alertsOn"))
        editor.saveNow()
        let reloaded = library.load(editor.project.id)
        XCTAssertNotNil(reloaded?.screen(named: "Extra"))
    }

    func testLibraryImportExportRoundTrip() throws {
        let editor = makeEditor("shop")
        let assetID = library.storeAsset(Data([1, 2, 3]), projectID: editor.project.id, ext: "png")
        editor.saveNow()
        let archive = try library.exportArchive(editor.project.id)
        let imported = try library.importFile(archive)
        XCTAssertNotEqual(imported.id, editor.project.id)
        XCTAssertEqual(imported.screens.count, editor.project.screens.count)
        XCTAssertEqual(library.assets(for: imported.id)[assetID], Data([1, 2, 3]))
        library.delete(imported.id)
    }
}

/// The SwiftUI runtime host used by previews and generated apps.
@MainActor
final class RuntimeStoreTests: XCTestCase {
    func testActionsDriveNavigationStateAndFeedback() async {
        var p = Templates.template("blank")!.makeProject(named: "Runtime")
        let second = Screen(name: "Second", children: [Node(type: .text, props: ["text": "Second screen"])])
        _ = p.addScreen(second)
        _ = p.ensureVariable("count", type: .number)
        let store = RuntimeStore(project: p, mode: .run, persistence: MemoryPersistence())
        await store.runAndWait([.increment("count", by: 2), .toast("Count is {{count}}"), .navigate(second.id)])
        XCTAssertEqual(store.state.value("count").numberValue, 2)
        XCTAssertEqual(store.toast?.message, "Count is 2")
        XCTAssertEqual(store.path(for: "stack:\(p.initialScreen!.id)").wrappedValue.last, second.id)
        await store.runAndWait([.back()])
        XCTAssertTrue(store.path(for: "stack:\(p.initialScreen!.id)").wrappedValue.isEmpty)
    }

    func testDesignModeNeverRunsActions() async {
        var p = Templates.template("blank")!.makeProject(named: "Design")
        _ = p.ensureVariable("count", type: .number)
        let store = RuntimeStore(project: p, mode: .design, persistence: MemoryPersistence())
        await store.runAndWait([.increment("count")])
        XCTAssertEqual(store.state.value("count").numberValue, 0)
    }
}
